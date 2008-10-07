#!/usr/bin/perl -w
###########################################################################
#   NAME: cqcc_chklive.pl
#   DESC: check that the cq/xml live server is up, if not, restart it
#   ARGS: n/a
#   RTNS: prn to STDERR if server process dead
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
#   globals that get inherited
###########################################################################
use Cwd;
BEGIN                                           # do this at compile time
{                                               # save off cmd header & dir
    ($cmdhdr, $cmddir) = ($0 =~ m|^(.*)[/\\]([^/\\]+)$|o) ? ($2, $1) : ($0, '.');
                                                # is cmddir full or relative?
    $libdir = $cmddir =~ m|^[/\\]|o ? $cmddir : cwd() . "/$cmddir";
    $libdir =~ s|\\|/|og;                       # conver \ -> /
}
local $cmdspc = $cmdhdr; $cmdspc =~ tr/!/ /c;   # command spacer
local $errhdr = "$cmdhdr: ERROR -";             # error header
local $errspc = $errhdr; $errspc =~ tr/!/ /c;   # error spacer
#local $dbghdr = "$cmdhdr: DEBUG -";             # debug header

###########################################################################
#   Perl goo
###########################################################################
use lib "$libdir";                              # push startup dir to @INC
use Sys::Hostname;                              # system info
require( 'cqsvrvars.pm' );                      # server variables
#require( 'cqsvrfuncs.pm' );                     # server functions
require( 'cqsys.pm' );                          # system-level functions
require( 'prndbghdr.pm' );

###########################################################################
#   globals
###########################################################################
my @passthru = ();                              # init pass-thru args
my $procerrs = '';                              # errs from CqSys pkg
my %procs    = ();                              # server processes
my $portpid  = ();                              # pid on same port
my $node     = lc( hostname() );                # machine name
my $mailsubj = "$CqSvr::mailerrsubj on '$node'"; # mail subject
                                                # prevent warnings on 1-use vars
my @tmp      = ( $CqSvr::mailerrsubj, $CqSvr::cqperl,
                 $CqSvr::port, $CqSvr::cpenvlang, $CqSvr::licenv,
                 $CqSvr::debug, $CqSys::debug,
                 $CqSvr::fulllogdir, $CqSvr::ipqfile,
               );

###########################################################################
#   user configurable globals
###########################################################################
local $debug    = 0;                            # debug flag
local $chkipq   = 0;                            # don't 
local $nomail   = 0;                            # don't send mail
local $statall  = 0;                            # status of all flag
local $useronly = 0;                            # user process flag
local $runnum   = 0;                            # running on alt port?
local $multisys = 0;                            # multi-sys from same src


###########################################################################
#   main()
###########################################################################
@passthru = ParseCmd( @ARGV );                  # pull out debug & pass-thru
($procerrs, %procs) = CqSys::FindSvrProcs( "$CqSvr::livename", 0 );

if ( $statall )                                 # svr procs stats
{
                                                # spew if no processes found
    die( "$errhdr no processes found!\n" ) if ( !%procs );
    foreach $proc ( sort( keys( %procs ) ) )    # go thru pids
    {
                                                # prn hdr, pid & args
        print( "$cmdhdr: $proc = $procs{$proc}\n" );
    }
    exit( 0 );                                  # stop here
}

ChkIpq( ) if ( $chkipq );                       # chk ipq files if enabled

                                                # match processes w/ port offset
$portpid = CqSys::MatchSvrPort( $runnum, %procs );

if ( !$portpid )                                # no matching procs found
{
    if ( @{$procerrs} )                         # errs from FindSvrProcs()
    {
        map( s/^(.*)$/$errhdr $1\n/, @{$procerrs} ); # slam errhdr on front of err
                                                # join errs & send via email
        CqSys::PrnBinMailMsg( 'ERROR: ' . join( '', @{$procerrs} ), \@CqSvr::mailerrto, "$mailsubj (main)", ($statall || $main::nomail), 1 );
    }
    else                                        # no errs & no matching procs
    {
        RestartSvr( $runnum, @passthru );       # restart interface
    }
}


###########################################################################
#   NAME: ParseCmd
#   DESC: parses the cmd line
#   ARGS: @ARGV
#   RTNS: verbose/debug flag, pass-thru args
###########################################################################
sub ParseCmd
{
    my @args = @_;                              # save @ARGV locally
    my @rtn = ();                               # init return array

    for ( my $i=0; defined( $args[$i] ); $i++ ) # go thru args
    {
        if ( $args[$i] =~ /^--?h/o )            # help requested
        {
            print( "USAGE: $cmdhdr [-d (#)|(-)-h|-i|-n|-p|$CqSvr::runswitch <#>|$CqSvr::sysswitch|-u|--*|*]\n" );
            print( "\t-d/ebug (#) run in debug mode (# - change debug level)\n" );
            print( "\t-h/elp      this help screen\n" );
            print( "\t-i/pq       check IPQ file backlog\n" );
            print( "\t-n/omail    don't send mail if error detected\n" );
            print( "\t-p/rint     just print running server processes\n" );
            print( "\t$CqSvr::runswitch/un #     run with alternate port/dir number added\n" );
            print( "\t$CqSvr::sysswitch/ys       run with multiple systems using same src\n" );
            print( "\t-u/ser      only look through current user's processes\n" );
            print( "\t--*/*       pass-through arguments\n" );
            exit( 0 );                          # get out'a here
        }
        elsif ( $args[$i] =~ /^-d/o )           # debug
        {
                                                # set global debug flag
            $main::debug = $CqSvr::debug = $CqSys::debug =
                $args[$i+1] =~ /^\d+$/ ? $args[++$i] : 1;
        }
        elsif ( $args[$i] =~ /^-i/o )           # check IPQ files
        {
            $chkipq = 1;                        # set global chk-IPQ-files flag
        }
        elsif ( $args[$i] =~ /^-n/o )           # don't send mail on error
        {
            $main::nomail = 1;                  # set global no-mail flag
        }
        elsif ( $args[$i] =~ /^-p/o )           # print all server procs
        {
            $statall = 1;                       # set global all flag
        }
                                                # run type
        elsif ( $args[$i] =~ /^$CqSvr::runswitch/o )
        {
            $runnum = $args[++$i];              # save next arg as run number
                                                # if runnum ! num | <1
            if ( $runnum =~ /\D/ || $runnum <= 0 )
            {
                warn( "$errhdr invalid run number '$runnum'!\n" );
                ParseCmd( '-h' );               # prn help & exit
            }
                                                # add port/run opts to pass thru
            push( @rtn, $args[$i-1], $args[$i] );
        }
                                                # multi-sys from same src
        elsif ( $args[$i] =~ /^$CqSvr::sysswitch/o )
        {
            $multisys = 1;                      # set global multi-sys flag
            push( @rtn, $args[$i] );            # add multi-sys opt to pass thru
        }
        elsif ( $args[$i] =~ /^-u/o )           # print status
        {
            $useronly = 1;                      # set global user flag
        }
        else                                    # unknown arg
        {
            $args[$i] =~ s/^--/-/o;             # remove extra -
            push( @rtn, $args[$i] );            # assume pass thru arg & save
        }
    }

    return( @rtn );                             # debug flag & pass-thru args
}


###########################################################################
#   NAME: ChkIpq
#   DESC: checks the IPQ files
#   ARGS: n/a
#   RTNS: n/a
###########################################################################
sub ChkIpq
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my $epoch = time();                         # current time
    my %ipqerrs = ();                           # new ipq errors
    my %olderrs = ();                           # old (aka known) ipq errors
    my %newerrs = ();                           # new errs + old errs still
    my $err     = '';                           # err rtn

    %ipqerrs = GenIpqErrList( $epoch );         # gen list of bad IPQ files
    ($err, %olderrs) = ReadIpqErrLog( );        # read old bad IPQ files
                                                # prn/mail & exit if read err
    CqSys::PrnBinMailMsg( $err, \@CqSvr::mailerrto, "$mailsubj (read ipq)", ($statall || $main::nomail), 1 ) if ( $err );
                                                # compare old&new IPQ err files
    %newerrs = CompareIpqErrs( $epoch, \%ipqerrs, \%olderrs );
    $err = WriteIpqErrLog( %newerrs );          # write IPQ errs
                                                # prn/mail & exit if write err
    CqSys::PrnBinMailMsg( $err, \@CqSvr::mailerrto, "$mailsubj (write ipq)", ($statall || $main::nomail), 1 ) if ( $err );
}


###########################################################################
#   NAME: GenIpqErrList
#   DESC: find IPQ files that are too old (or 0 size)
#   ARGS: epoch
#   RTNS: 2d-hash: file=>{mod,date,size}
###########################################################################
sub GenIpqErrList
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my $epoch = $_[0];                          # current time
    my $size  = 0;                              # file size
    my $mod   = 0;                              # file mod date
    my %errs  = ();                             # init rtn hash

                                                # go thru ipq files
    foreach $ipq ( <$CqSvr::fulllogdir/$CqSvr::ipqfile*> )
    {
        ($size, $mod) = (stat( $ipq ))[7,9];    # save file size & mod time
                                                # old file | new 0-len file
        if ( $epoch - $mod > $CqSvr::chkfreq || !$size )
        {
                                                # save file info to hash=>hash
            $errs{$ipq} = { mod  => $mod,
                            date => $epoch,
                            size => $size, };
        }
    }

    return( %errs );                            # return errors
}


###########################################################################
#   NAME: ReadIpqErrLog
#   DESC: read IPQ err log & save into 2d-hash
#   ARGS: n/a
#   RTNS: err status, hash (file=>{mod,date,size})
###########################################################################
sub ReadIpqErrLog
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my %ipqlog = ();                            # init rtn hash

                                                # if IPQ err log exists
    if ( -f "$CqSvr::fulllogdir/$CqSvr::ipqerrfile" )
    {
                                                # open ipq err log
        if ( open( IPQERR, "<$CqSvr::fulllogdir/$CqSvr::ipqerrfile" ) )
        {
            foreach $line ( <IPQERR> )          # go thru ea line
            {
                                                # parse file|mod|date|size
                if ( $line =~ /^([^,]+),(\d+),(\d+),(\d+)\s*$/ )
                {
                    $ipqlog{$1} = { mod  => $2,
                                    date => $3,
                                    size => $4, };
                }
            }
            close( IPQERR );                    # close ipq err log
        }
        else                                    # open failed
        {
            return( "Unable to read from IPQ error log file '$CqSvr::ipqerrfile'!" );
        }
    }

    return( '', %ipqlog );                      # rtn no err, file=>{...}
}


###########################################################################
#   NAME: CompareIpqErrs
#   DESC: compare known IPQ errs w/ new IPQ errs
#   ARGS: epoch, ref new ipq errs, ref old ipq errs
#   RTNS: all bad IPQs as 2d-hash: (file=>{mod,date,size})
###########################################################################
sub CompareIpqErrs
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my $epoch  = $_[0];                         # current time
    my %new    = %{$_[1]};                      # new bad IPQ files
    my %old    = %{$_[2]};                      # old/known bad IPQ files
    my %diff   = ();                            # hash for diff'ing
    my %rtn    = ();                            # rtn hash
    my @newrep = ();                            # new ipqs to report
    my @oldrep = ();                            # old ipqs to re-report
    my $msgbody = '';                           # email/prn message body

    grep( $diff{$_}++, keys( %new ) );          # read new files
    grep( $diff{$_}--, keys( %old ) );          # read old files

    foreach $file ( keys( %diff ) )             # go thru all files
    {
        if ( $diff{$file} > 0 )                 # new files
        {
            $rtn{$file} = $new{$file};          # save file info
            push( @newrep, $file );             # add to new report array
        }
        elsif ( $diff{$file} == 0 )             # old file, still there
        {
            $rtn{$file} = $old{$file};          # save old file info
                                                # if warn time exceeded
            if ( $epoch - ${$rtn{$file}}{date} > $CqSvr::chkwarn )
            {
                ${$rtn{$file}}{date} = $epoch;  # reset notify counter
                push( @oldrep, $file );         # add to old report array
            }
        }
    }

    if ( @newrep )                              # if new ipq errs
    {
        $msgbody .= 'The following IPQ files have not been cleaned up after ';
        $msgbody .= $CqSvr::chkfreq/60 . " minutes.  This is indicative of a problem with one of the files themselves or the CQ/XML Queue Manager.\n\t";
        $msgbody .= join( "\n\t", @newrep ) . "\n\n";
    }

    if ( @oldrep )                              # old reported files
    {
        $msgbody .= 'The following IPQ files were reported ';
        $msgbody .= $CqSvr::chkwarn/60 . " minutes ago but have not been addressed.\n\t";
        $msgbody .= join( "\n\t", @oldrep ) . "\n\n";
    }

                                                # email/prn errs
    CqSys::PrnBinMailMsg( $msgbody, \@CqSvr::mailerrto, "$mailsubj (ipq)", ($statall || $main::nomail), 0 ) if ( $msgbody );

    return( %rtn );                             # rtn existing ipq errs
}


###########################################################################
#   NAME: WriteIpqErrLog
#   DESC: writes the ipq errors to file
#   ARGS: hash of problem ipq files (file=>{mod,date,size}
#   RTNS: errs
###########################################################################
sub WriteIpqErrLog
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my %ipqerrs = @_;                           # bad ipqs

    return( '' ) if ( !%ipqerrs );              # rtn nada if no errs

                                                # open ipq err log for write
    if ( open( IPQERR, ">$CqSvr::fulllogdir/$CqSvr::ipqerrfile" ) )
    {
                                                # write header line (for humans)
        print( IPQERR "FILE,MODIFIED,CHECKED,SIZE\n" );
        foreach $file ( keys( %ipqerrs ) )      # go thru ipq errs
        {
                                                # print "file,mod,date,size"
            print( IPQERR "$file,${$ipqerrs{$file}}{mod},${$ipqerrs{$file}}{date},${$ipqerrs{$file}}{size}\n" );
        }
        close( IPQERR );                        # close IPQ err log
    }
    else                                        # err opening ipq err log
    {
        return( "Unable to write to IPQ error log file '$CqSvr::ipqerrfile'!" );
    }

    return( '' );                               # return no errors, hooray
}


###########################################################################
#   NAME: RestartSvr
#   DESC: restarts the cq/xml live server
#   ARGS: run/port num, pass-through args from cmd line
#   RTNS: n/a
###########################################################################
sub RestartSvr
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my $port = $CqSvr::port + shift( @_ );      # port to chk
                                                # err msg to send
    my $mailmsg = 'Server process not running! Restarting...';

    if ( CqSys::PortInUse( $port ) )            # if the port is in use
    {
        $mailmsg .= "\n$errhdr port in use.  Unable to restart!";

                                                # throw err (w/o restart)
        CqSys::PrnBinMailMsg( $mailmsg, \@CqSvr::mailerrto, "$mailsubj (port)", ($statall || $main::nomail), 1 );
    }
    else
    {
                                                # throw err
        CqSys::PrnBinMailMsg( $mailmsg, \@CqSvr::mailerrto, "$mailsubj (process)", ($statall || $main::nomail), 0 );
        $ENV{LANG} = $CqSvr::cpenvlang;         # explicitely set code page
        $ENV{LM_LICENSE_FILE} = $CqSvr::licenv; # set license servers trio
                                                # startup server w/ passthru
        exec( "$CqSvr::cqperl $cmddir/$CqSvr::livename @_"  );
    }
}
