#!/usr/bin/perl
###########################################################################
#   NAME: cqcc_queued.pl
#   DESC: reads XML log files dropped by cqcc_live.pl and performs CQ actions
###########################################################################
#   Copyright 2005 Mentor Graphics Corporation
#   
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#   
#       http://www.apache.org/licenses/LICENSE-2.0
#   
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
###########################################################################

###########################################################################
#   Perl goo
###########################################################################
require 5.002;                                  # need Perl5 for new sockets
use Cwd;                                        # current dir
BEGIN                                           # do this at compile time
{                                               # save off cmd header & dir
    ($cmdhdr, $cmddir) = ($0 =~ m|^(.*)[/\\]([^/\\]+)$|o) ? ($2, $1) : ($0, '.');
                                                # is cmddir full or relative?
    $libdir = $cmddir =~ m|^[/\\]|o ? $cmddir : cwd() . "/$cmddir";
    $libdir =~ s|\\|/|og;                       # convert \ -> /
}
use lib "$libdir";                              # push startup dir to @INC
use FileHandle;                                 # non-buffer as obj method
use Socket;                                     # socket nirvana
use Sys::Hostname;                              # system info
use XML::Mini::Document;                        # XML parser
require( 'cqsvrvars.pm' );                      # server variables
require( 'cqsvrfuncs.pm' );                     # server functions
require( 'cqxml.pm' );                          # functions to parse/process XML
require( 'cqsys.pm' );                          # system-level functions
autoflush STDERR 1;                             # don't buffer STDERR
                                                # prevent warnings on 1-use vars
my @tmp = ( $CqSvr::commroot, $CqSvr::logdir, $CqSvr::osiswin,
            $CqSvr::publogdir, $CqSvr::queuename,
            $CqXml::debug, $CQ::debug, $CqSvr::debug, $CqSys::debug,
            %CqSvr::modperms, %CqSvr::enckeys, $CqSvr::sysmsg,
            $CqSvr::mailerrsubj,
); @tmp = ();

###########################################################################
#   globals
###########################################################################
$| = 1;                                         # don't buffer output
local $cmdspc = $cmdhdr; $cmdspc =~ tr/!/ /c;   # basename spacing
local $errhdr = "\a$cmdhdr: ERROR -";           # error header
local $errspc = $errhdr; $errspc =~ tr/!/ /c;   # error header spacing
#local $wrnhdr = "\a$cmdhdr: WARNING -";         # warning header
#local $dbghdr = "$cmdhdr: DEBUG -";             # debug header
local $logdir = "$libdir/$CqSvr::logdir";       # log dir
local $exitval = 0;                             # exit val (default = 0)
local $debug = 0;                               # debug (default = disabled)
local $runnum = '';                             # running on alt port?
local $multisys = 0;                            # multi sys from same src
local $epoch = time();                          # start time as epoch
local @time = (gmtime( $epoch ))[5,7];          # save yr & yr-day
                                                # reformat time
local $yrday = sprintf( "%02d%03d", $time[0]-100, $time[1] );
local $logfh = undef;                           # log filehandle ref
local @qfiles = ();                             # queue files
local $publogdir = $CqSvr::publogdir;           # save pkg pub log prefix
local $permchk = 1;                             # permissions enabled by default
local $syserrs = '';                            # errs from CqSys pkg
local %procs = ();                              # server processes
local @pids = ();                               # pids of svr procs
local $curpid = 0;                              # pid of this process
local @syswait = ();                            # system wait?

###########################################################################
#   main()
###########################################################################
ParseCmd( @ARGV );                              # parse cmd line, set globals
if ( !$CqSvr::osiswin )                         # lots of UNIX stuff coming up
{
                                                # chk if more queue mgrs running
    ($syserrs, %procs) = CqSys::FindSvrProcs( "$CqSvr::queuename", 0 );
    if ( @{$syserrs} )                          # if errs rtn'd
    {
        map( s/^(.*)$/$errhdr $1\n/, @{$errs} ); # slam errhdr on front of errs
        die( "$errhdr unable to determine status of existing processes!", join( '', @{$errs} ) );
    }
                                                # find matching svr
    @pids = CqSys::MatchSvrArgs( $runnum, $multisys, %procs );
    $curpid = $$;                               # perl spews on 3 $'s in next RE
    if ( grep( !/^$curpid$/, @pids ) )          # if pid ! current process
    {
        CqSvr::GenSvrLog( $logdir, $CqSvr::qfile, {status => 'warning'}, 'queue server already running' );
        if ( !$quiet )                          # if noisy
        {
            print( "$main::cmdhdr (PID:$$) ", CqSvr::ShortDateNTime(), "\n" );
            print( "$main::cmdspc queue server process detected: ", (grep( !/^$curpid$/, @pids )), "\n" );
        }
        exit( 0 );                              # stop here
    }
}

die( "$exitval\n" ) if ( $exitval = CqSvr::MkDirTree( "$logdir/$CqSvr::arcdir/$yrday" ) );
                                                # make pub log dir
die( $exitval ) if ( $exitval = CqSvr::MkDirTree( $publogdir ) );
$CqSvr::sysmsg = CqSvr::ReadSysMsg();           # read system status message
                                                # open logfile save fh ref
$logfh = CqSvr::OpenLog( "$publogdir/${CqSvr::filepre}_q${yrday}.xml", $quiet );
                                                # prn "started" to log file
CqSvr::Log2Xml( $logfh, "svr$epoch", {date => CqSvr::ShortDateNTime(), status => 'started', pid => $$}, '', 'NOCLOSE' );
                                                # if queue files waiting
if ( @qfiles = <$logdir/${CqSvr::qfile}[0-9][0-9][0-3][0-9][0-9][ns][0-9][0-9][0-9][0-9][0-9][0-9]> )
{
    if ( @syswait = CqSvr::ChkSysWait() )       # check if sys wait file around
    {
                                                # overwrite <svr>'s '\n' on Win
        seek( $logfh, -1, 2 ) if $CqSvr::osiswin;
                                                # print system waiting...
        print( $logfh "  <system cqtan='$syswait[0]' status='error'>$syswait[1]</system>" );
    }
    else                                        # system waits for nobody!
    {
                                                # read ip mod perms unless skip
        %CqSvr::modperms = CqSvr::ReadIpModPerms() if ( $permchk );
        %CqSvr::enckeys = CqSvr::ReadEncKeys(); # read pswd encryption keys
        ProcessQueued( @qfiles );               # process the queued file
    }
}
else                                            # no files waiting
{
    seek( $logfh, -1, 2 ) if $CqSvr::osiswin;   # overwrite <svr>'s '\n' on Win
    print( $logfh "queue empty" );              # prn "empty" status
}
print( $logfh "</svr$epoch>\n" );               # close server element
print( $logfh "</$CqSvr::rootelem>" );          # prn root elem close to log
close( $logfh );                                # close log file
RecordLiveLog ( <$logdir/${CqSvr::lfile}[0-9][0-9][0-3][0-9][0-9][ns][0-9][0-9][0-9][0-9][0-9][0-9]> ) if ( !@syswait );


###########################################################################
#   NAME: ParseCmd
#   DESC: parse the command line
#   ARGS: @ARGV
#   RTNS: n/a
###########################################################################
sub ParseCmd
{
    my @args = @_;                              # save @ARGV locally
    my $sysdir = '';                            # multi sys ext

    for ( my $i=0; defined( $args[$i] ); $i++ ) # go thru args
    {
        if ( $args[$i] =~ /^-h/o )              # if help requested
        {
            select( STDERR ) if ( $exitval );   # prn to ERR if err flagged
                                                # prn usage
            print( "USAGE: $cmdhdr [-d|-h|-p|-q|$CqSvr::runswitch <#>|$CqSvr::sysswitch]\n" );
            print( "\t-d/ebug  enable debug output\n" );
            print( "\t-h/elp   this help screen\n" );
            print( "\t-p/erm   disable permission checking\n" );
            print( "\t-q/uiet  don't print start/stop messages\n" );
            print( "\t$CqSvr::runswitch/un #  run with alternate port/dir number added\n" );
            print( "\t$CqSvr::sysswitch/ys    multiple systems using same src\n" );
            exit( $exitval );                   # exit
        }
        elsif ( $args[$i] =~ /^-d/o )           # if debug requested
        {
            $debug = $CqXml::debug = $CQ::debug = $CqSvr::debug = $CqSys::debug = 1;
        }
        elsif ( $args[$i] =~ /^-p/o )           # disable permission checking
        {
            $permchk = 0;                       # set flag
        }
        elsif ( $args[$i] =~ /^-q/o )           # quiet please
        {
            $quiet = 1;                         # set quiet flag
        }
                                                # run type
        elsif ( $args[$i] =~ /^$CqSvr::runswitch/o )
        {
            $runnum = $args[++$i];              # save nxt arg as runtype global
                                                # if unknown run type
                                                # if run num ! num | <1
            if ( $runnum =~ /\D/ || $runnum <= 0 )
            {
                warn( "$errhdr invalid run number '$runnum'!\n" );
                $exitval = 1;                   # set bad exit val
                ParseCmd( '-h' );               # prn help & exit
            }
        }
                                                # multi sys from 1 src loc
        elsif ( $args[$i] =~ /^$CqSvr::sysswitch/o )
        {
            use Sys::Hostname;                  # now we need host name
            $sysdir = '_' . lc( hostname() );   # use host as dir ext
            $multisys = 1;                      # set global flag
        }
        else                                    # unknown arg
        {
            warn( "$errhdr unknown argument '$args[$i]'!\n\n" );
            $exitval = 1;                       # set bad exit val
            ParseCmd( '-h' );                   # prn help & exit
        }
    }

    $logdir .= "$runnum$sysdir";                # add log dir exts
    $publogdir .= "$runnum$sysdir";             # add pub log dir exts

    if ( ! -d $logdir )                         # can't find log dir
    {
        warn( "$errhdr unable to locate log directory at:\n" );
        warn( "$errspc $logdir!\n\n" );
        $exitval = 1;                           # set bad exit val
        ParseCmd( '-h' );                       # prn help & exit
    }
}


###########################################################################
#   NAME: ProcessQueued
#   DESC: opens queued files & sends contents to get worked on
#   ARGS: filelist
#   RTNS: n/a
###########################################################################
sub ProcessQueued
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my @files = @_;                             # list of files to read
    my $cqtan = '';                             # init cqtan

    foreach $file ( sort( @files ) )            # go thru file list (in order)
    {
        $cqtan = $file;                         # cqtan is part of filename
        $cqtan =~ s/^.*$CqSvr::qfile//;         # strip off non-cqtan part

        if ( open( XML, "<$file" ) )            # if open succeeded
        {
                                                # read in xml & pass it
            ReadCmd( $cqtan, join( '', <XML> ) );
            close( XML );                       # close xml file
            $file =~ m#($CqSvr::qfile$cqtan)$#; # get file leaf name
                                                # move file to archive dir
            rename( "$file", "$logdir/$CqSvr::arcdir/$yrday/$1" );
        }
        else                                    # open failed
        {
                                                # record err
            CqSvr::Log2Xml( $logfh, $cqtan, {status => 'error'}, "unable to read '$cqtan'" );
            warn( "$errhdr unable to read queued file '$file'!\n" );
            next;                               # skip this file
        }
    }
}


###########################################################################
#   NAME: ReadCmd
#   DESC: perform the commands passed by the client
#   ARGS: cqtan, cq/xml command
#   RTNS: n/a
###########################################################################
sub ReadCmd
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $cqtan = $_[0];                          # cqtan
    my $cmd = $_[1];                            # xml cmd
    my $xmldoc = XML::Mini::Document->new();    # create XML parse obj
    my %xmlhash = ();                           # cq XML parse obj as hash
    my %cqcommhash = ();                        # cq comm xml parse obj as hash
    my @xmlrtn = ();                            # init status in process rtn
    my $err = '';                               # err str rtn'd from funcs
    my $xmlrtnstr = '';                         # cq exec rtn xml

                                                # special case: q-svr running 2x
    if ( $cmd !~ /^<$CqSvr::rootelem>/ && $cmd =~ /<svr\d+/ )
    {
        print( $logfh $cmd );                   # prn other queue svr message
        return();                               # we're finished in here
    }

    eval                                        # now call the XML parser
    {
        $xmldoc->parse( $cmd );
        %xmlhash = %{${$xmldoc->toHash()}{$CqSvr::rootelem}};
        %cqcommhash = %{${$xmldoc->toHash()}{$CqSvr::commroot}};
    };

                                                # shove empty vals if not set
    $xmlhash{db} = '' if ( !defined( $xmlhash{db} ) );
    $xmlhash{login} = '' if ( !defined( $xmlhash{login} ) );

    if ( $@ || !%xmlhash || !%cqcommhash )      # if the parser failed
    {
                                                # log err & send email
        LogNSendErr( $logfh, $cqtan, $cmd, $xmlhash{db}, $xmlhash{login}, $cqcommhash{client}, $cqcommhash{ip}, 'unable to parse XML', 'error', $xmlhash{'email-fail'} );
        return();                               # get out'a here
    }
                                                # break xml into exec cmds
    ($err, @xmlrtn) = CqXml::ReStructElems( 'no', $cqcommhash{ip}, %xmlhash );
    if ( $err )                                 # if err breaking xml
    {
                                                # log err & send email
        LogNSendErr( $logfh, $cqtan, $cmd, $xmlhash{db}, $xmlhash{login}, $cqcommhash{client}, $cqcommhash{ip}, $err, 'error', $xmlhash{'email-fail'} );
    }
    elsif ( $#xmlrtn <= 0 )                     # if no queued actions in xml
    {
        CqSvr::Log2Xml( $logfh, $cqtan, {db => $xmlhash{db}, login => $xmlhash{login}, client => $cqcommhash{client}, ip => $cqcommhash{ip}, status => 'skipped'}, 'no queued actions found' );
    }
    else                                        # found some queued actions
    {
                                                # exec the cmds & save rtn xml
        ($xmlrtnstr, $err) = CqXml::CqExecXml( $cqtan, @xmlrtn );
                                                # write status to log file
        if ( $err )                             # if >0 errs
        {
            LogNSendErr( $logfh, $cqtan, $cmd, $xmlhash{db}, $xmlhash{login}, $cqcommhash{client}, $cqcommhash{ip}, $xmlrtnstr, 'processed', $xmlhash{'email-fail'} );
        }
        else                                    # no errors
        {
            CqSvr::Log2Xml( $logfh, $cqtan, {db => $xmlhash{db}, login => $xmlhash{login}, client => $cqcommhash{client}, ip => $cqcommhash{ip}, status => 'processed'}, "\n$xmlrtnstr" );
        }
    }
}


###########################################################################
#   NAME: LogNSendErr
#   DESC: logs & emails an error
#   ARGS: log filehdl, cq tan, xml cmd, db, login, client, ip, status, err msg
#   RTNS: n/a
###########################################################################
sub LogNSendErr
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $logfh  = $_[0];                         # log filehandle
    my $cqtan  = $_[1];                         # cq tan
    my $xmlcmd = $_[2];                         # xml cmd
    my $db     = $_[3];                         # db
    my $login  = $_[4];                         # cq login
    my $client = $_[5];                         # client machine name
    my $ip     = $_[6];                         # client ip
    my $errmsg = $_[7];                         # err msg
    my $status = $_[8];
    my $email  = $_[9];                         # email errs to
    my $line   = '-'x10;                        # a nice ASCII line
    my @errs   = (grep( /status='error'/, split( "\n", $errmsg ) ));

                                                # log the failure
    CqSvr::Log2Xml( $logfh, $cqtan, {db => $db, login => $login, client => $client, ip => $ip, status => $status}, $errmsg );

                                                # remove password
    $xmlcmd =~ s/( password=)("[^"]*"|'[^']*')/$1'*****'/;
                                                # jam a line between cmd & comm
    $xmlcmd =~ s/(<\/$CqSvr::rootelem>)\s+(<$CqSvr::commroot[^>]+>)/$1\n$line Connection Information $line\n$2/;

    $errmsg = join( "\n", @errs ) if ( @errs ); # save parsed errs if found
                                                # add separator btwn err & xml
    $errmsg .= "\n$line Original Command $line\n";
    $errmsg .= $xmlcmd;                         # now append cmd/comm to msg

                                                # send err & rm 'ok's
    CqSys::PrnBinMailMsg( "$line Error Message $line\n$errmsg", [$email], $CqSvr::mailerrsubj, 0, 0 ) if ( defined( $email ) );
}


###########################################################################
#   NAME: RecordLiveLog
#   DESC: takes all the live logs and joins them in a public log
#   ARGS: live log files
#   RTNS: n/a
###########################################################################
sub RecordLiveLog
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my @files = @_;                             # save file list
    my $llogfh = undef;                         # live log filehandle

    if ( @files )                               # if files to process
    {
                                                # open public live log
        $llogfh = CqSvr::OpenLog( "$publogdir/${CqSvr::filepre}_l${yrday}.xml", $quiet );
                                                # go thru live log files
        foreach $file ( SortFilesByModDate( @files ) )
        {
            if ( open( LIVEXML, "<$file" ) )    # if private live log open ok
            {
                print( $llogfh <LIVEXML> );     # print private log to pub log
                close( LIVEXML );               # close private log
                                                # parse leaf name
                $file =~ m#($CqSvr::lfile[^\\/]+)$#;
                                                # rename file to archive
                rename( "$file", "$logdir/$CqSvr::arcdir/$yrday/$1" );
            }
            else                                # open failed
            {
                                                # save error to public log
                CqSvr::Log2Xml( $llogfh, "svr$epoch", {date => CqSvr::ShortDateNTime(), status => 'error', pid => $$}, "unable to read live log '$file'!" );
                warn( "$errhdr unable to read live log file '$file'!\n" );
            }
        }
        print( $llogfh "</$CqSvr::rootelem>" ); # append closing root elem
        close( $llogfh );                       # close public log
    }
}


###########################################################################
#   NAME: SortFilesByModDate
#   DESC: sorts a list of files by modification date
#   ARGS: list of files
#   RTNS: sorted list of files
###########################################################################
sub SortFilesByModDate
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my @files = @_;                             # save file list
    my %moddate = ();                           # init tmp mod date hash
    my $mdate = '';                             # init tmp mod date
    my @rtn = ();                               # init return array

    foreach $file ( @files )                    # go thru file list
    {
        $mdate = (stat( $file ))[9];            # get mod date of file
                                                # inc date while same date found
        $mdate++ while ( defined( $moddate{$mdate} ) );
        $moddate{$mdate} = $file;               # save date & filename
    }

    foreach $date ( sort( keys( %moddate ) ) )  # go thru files by mod date
    {
        push( @rtn, $moddate{$date} );          # save to return array
    }

    return( @rtn );                             # return files by mod date
}
