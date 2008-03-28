#!/usr/bin/perl
###########################################################################
#   NAME: cqcc_live.pl
#   DESC: reads XML on a socket to perform CQ actions
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
    $libdir =~ s|\\|/|og;                       # conver \ -> /
}
use lib "$libdir";                              # push startup dir to @INC
use FileHandle;                                 # non-buffer as obj method
use Socket;                                     # socket nirvana
use Sys::Hostname;                              # system info
use XML::Mini::Document;                        # XML parser
require( 'cqsvrvars.pm' );                      # server-wide variables
require( 'cqsvrfuncs.pm' );                     # server-wide functions
require( 'cqxml.pm' );                          # functions to parse/process XML
$SIG{HUP} = 'IGNORE' if ( defined( $SIG{HUP} ) );
$SIG{QUIT} = \&CtrlC;                           # kill server on quit or stop
$SIG{TERM} = \&CtrlC; 
$SIG{CHLD} = 'IGNORE';                          # ignore zombie children
$SIG{INT} = \&CtrlC;                            # catch ^C
autoflush STDOUT 1;                             # don't buffer STDOUT
autoflush STDERR 1;                             # don't buffer STDERR
                                                # prevent warnings on 1-use vars
my @tmp = ( $CqSvr::recuk, $CqSvr::rtnleadspc, $CqSvr::atrbkey, $CqSvr::tcpproto, $CqSvr::commroot, $CqSvr::filepre, $CqSvr::port, $CqSvr::logdir, $CqXml::debug, $CQ::debug, $CqSvr::debug, %CqSvr::modperms, %CqSvr::enckeys, ); @tmp = ();

###########################################################################
#   globals
###########################################################################
local $errhdr = "\a$cmdhdr: ERROR -";           # error header
local $errspc = $errhdr; $errspc =~ tr/!/ /c;   # error header spacing
local $wrnhdr = "\a$cmdhdr: WARNING -";         # warning header
local $dbghdr = "$cmdhdr: DEBUG -";             # debug header
local $port = $CqSvr::port;                     # port number
local $runnum = '';                             # running as alt num
local $logdir = "$libdir/$CqSvr::logdir";       # log dir
local $exitval = 0;                             # exit val (default = 0)
local $debug = 0;                               # debug (default = disabled)
local $hostname = lc( hostname() );             # local host
#local $hostip = inet_ntoa( scalar( gethostbyname( $hostname ) ) );
local $cqtan = 0;                               # init CQ TransAction Number
local @syswait = ();                            # system wait?
local $forksocket = 0;                          # forking disabled by default
local $permchk = 1;                             # permissions enabled by default

###########################################################################
#   main()
###########################################################################
ParseCmd( @ARGV );                              # parse cmd line
                                                # die if make dir | init failed
die( "$exitval\n" ) if ( $exitval = CqSvr::MkDirTree( "$logdir" ) );

                                                # print "started" to STDOUT
print( "$cmdhdr (PID:$$) started ", CqSvr::ShortDateNTime(), "\n" );
                                                # print "started" to log
CqSvr::GenSvrLog( $logdir, $CqSvr::lfile, {status => 'started'} );
                                                # create internet stream socket
socket( SSOCKET, PF_INET, SOCK_STREAM, $CqSvr::tcpproto )
    or die( "socket: $!" );
                                                # allow bind to port in use
setsockopt( SSOCKET, SOL_SOCKET, SO_REUSEADDR, 1 )
    or die( "setsockopt: $!" );
                                                # bind server socket to address
bind( SSOCKET, sockaddr_in( $port, INADDR_ANY ) )
    or die( "bind: $! ($port)!" );
                                                # queue SOMAXCONN connections
listen( SSOCKET, SOMAXCONN ) or die( "listen: $!" );
autoflush SSOCKET 1;                            # don't buffer server socket

while ( $paddr = accept( CSOCKET, SSOCKET ) )   # while incoming sockets are ok
{
    my ($port, $caddr) = sockaddr_in( $paddr ); # unpack client socket address
    my $clientip = inet_ntoa( $caddr );         # resolve client socket to ip
                                                # resolve client socket to host
    my $clienthost = lc( gethostbyaddr( $caddr, AF_INET ) ); # 
    my $pid = 0;                                # init PID variable
    autoflush CSOCKET 1;                        # don't buffer client socket
    $cqtan = GenCqTan( $cqtan );                # inc our counter

                                                # read ip mod perms unless skip
    %CqSvr::modperms = CqSvr::ReadIpModPerms() if ( $permchk );
    %CqSvr::enckeys = CqSvr::ReadEncKeys();     # read pswd encryption keys
    $CqSvr::sysmsg = CqSvr::ReadSysMsg();       # read system status message
    if ( @syswait = CqSvr::ChkSysWait() )       # check if sys wait file around
    {
                                                # prn msg thru socket
        PrnRtnXml( \*CSOCKET, '', '', $cqtan, $clienthost, $clientip, 
            "  <system cqtan='$syswait[0]' status='error'>$syswait[1]</system>\n" );
        shutdown( CSOCKET, 2 );                 # stop read/write on socket
        close( CSOCKET );                       # close client socket
    }
                                                # if fork enabled & fork failed
    elsif ( $forksocket && !defined( $pid = fork() ) )
    {
        die( "$errhdr Cannot create child process\n" );
    }
    elsif ( !$pid )                             # child process does actual work
    {
        print( "$dbghdr child pid = $$\n" ) if ( $debug );
        my $csfh = \*CSOCKET;                   # child socket filehandle ref
        my $done = 0;                           # done reading on socket?
        my $cmd = '';                           # tmp var to save whole cmd
        my $rin = '';                           # select READ bitmask
        my $rout = '';                          # select READ bitmask out

        vec( $rin, fileno( CSOCKET ), 1 ) = 1;  # assign child bitmask to $rin
                                                # ready for read & data in bufr
        while ( (select( $rout=$rin, undef, undef, 0.1 ))[0]) 
        {
            recv( CSOCKET, $_, 1024, 0 );       # Put data into $_
            last if (! $_);                     # Done if there's No more Data
                                                # prn message to STDOUT
            #print( "$cmdhdr command received from $clienthost ($clientip:$port)\n" );
            $cmd .= $_;                         # add line of XML to var
                                                # if /root
            last if ( $_ =~ /<\/$CqSvr::rootelem>/ );
        } 
        shutdown( CSOCKET, 0 );                 # stop reading on socket
                                                # read command from socket
        ReadCmd( $csfh, $clienthost, $clientip, $port, $cqtan, $cmd );
        shutdown( CSOCKET, 2 );                 # stop read/write on socket
        close( CSOCKET );                       # close client socket
        exit( 0 ) if ( $forksocket );           # end child proc if forked child
    }                                           # end of child process
}
close( CSOCKET );                               # explicitly close client socket

                                                # log err & die
CqSvr::GenSvrLog( $logdir, $CqSvr::lfile, {error => 'problem accepting on socket'} );
die( "$errhdr cannot accept on socket: $!\n" ); # big problems!!!

###########################################################################
#   NAME: ParseCmd
#   DESC: parse the command line
#   ARGS: @ARGV
#   RTNS: n/a
###########################################################################
sub ParseCmd
{
    my @args = @_;                              # save @ARGV locally
    my $sysdir = '';                            # system dir ext

    for ( my $i=0; defined( $args[$i] ); $i++ ) # go thru args
    {
        if ( $args[$i] =~ /^-h/o )              # if help requested
        {
            select( STDERR ) if ( $exitval );   # prn to ERR if err flagged
                                                # prn usage
            print( "USAGE: $cmdhdr [-c <#>|-d|-dv|-f|-h|-p|$CqSvr::runswitch <#>|-s]\n" );
            print( "\t-c/qtan #  start cqtan numbers at '#'\n" );
            print( "\t-d/ebug    enable debug output\n" );
            print( "\t-dv/erbose enable verbose debug output\n" );
            print( "\t-f/ork     fork connected sockets\n" );
            print( "\t-h/elp     this help screen\n" );
            print( "\t-p/erms    disable permission checking\n" );
            print( "\t${CqSvr::runswitch}/un #    run with alternate port/dir number added\n" );
            print( "\t-s/ys      multiple systems using same src\n" );
            exit( $exitval );                   # exit
        }
        elsif ( $args[$i] =~ /^-c/o )           # cqtan reset
        {
                                                # if 2nd & 2nd arg is num, save
            $cqtan = $args[++$i] if ( defined( $args[$i+1] ) && $args[$i+1] =~ /^\d+$/ );
        }
        elsif ( $args[$i] =~ /^-dv/o )          # if debug/verbose requested
        {
            $debug = $CqXml::debug = $CQ::debug = $CqSvr::debug = 2;
        }
        elsif ( $args[$i] =~ /^-d/o )           # if debug requested
        {
                                                # enable debug
            $debug = $CqXml::debug = $CQ::debug = $CqSvr::debug = 1;
        }
        elsif ( $args[$i] =~ /^-f/o )           # fork socket connection enabled
        {
            $forksocket = 1;                    # set flag
        }
        elsif ( $args[$i] =~ /^-p/o )           # disable permission checking
        {
            $permchk = 0;                       # set flag
        }
                                                # run type
        elsif ( $args[$i] =~ /^$CqSvr::runswitch/o )
        {
            $runnum = $args[++$i];              # save next arg as run number
                                                # if run num ! num | <1
            if ( $runnum =~ /\D/ || $runnum <= 0 )
            {
                warn( "$errhdr invalid run number '$runnum'!\n" );
                $exitval = 1;                   # set bad exit val
                ParseCmd( '-h' );               # prn help & exit
            }
            $port += sprintf( "%d", $runnum );  # add num to port num
        }
        elsif ( $args[$i] =~ /^-s/o )           # multi sys from 1 src loc
        {
            $sysdir = "_$hostname";             # append host to log dir
        }
        else                                    # unknown arg
        {
            warn( "$errhdr unknown argument '$args[$i]'!\n\n" );
            $exitval = 1;                       # set bad exit val
            ParseCmd( '-h' );                   # prn help & exit
        }
    }
    $logdir .= "$runnum$sysdir";                # add log dir exts
}


###########################################################################
#   NAME: GenCqTan
#   DESC: gen next cqtan, so queue files don't get overwritten
#   ARGS: current cqtan
#   RTNS: cqtan number
###########################################################################
sub GenCqTan
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $cqtanin = $_[0];                        # save current cqtan
    my @date = gmtime( time() );                # GMT date
                                                # reformat date to match q files
    my $datestr = sprintf( "%02d%03d", $date[5]-100, $date[7] );
    my $cqtannum = '000000';                    # reformat cqtan num
    my @files = ();                             # 

    if ( $cqtanin =~ /^(\d{5})[a-z](\d{6})$/ )  # cqtan in known format?
    {
        if ( $datestr eq $1 )                   # if dates match (if !, use 0s)
        {
            $cqtannum = sprintf( "%06d", $2+1 ); # inc ctr
        }
    }
    else                                        # prob w/ num or svr restart
    {
                                                # get all filenames from today
        @files = ( <$logdir/$CqSvr::ipqfile$datestr*>,
                   <$logdir/$CqSvr::qfile$datestr*>,
                   <$logdir/$CqSvr::arcdir/$datestr/$CqSvr::qfile$datestr*>,
                   <$logdir/$CqSvr::lfile$datestr*>,
                   <$logdir/$CqSvr::arcdir/$datestr/$CqSvr::lfile$datestr*>,
                 );
                                                # find name exact match
        @files = grep( m#/$CqSvr::filepre.\w+$datestr\w\d{6}$#, @files );
        map( s/^.*\D//, @files );               # strip off date & [ns]
        @files = sort( @files );                # sort so newest is last
                                                # if some files & num match
        if ( $#files >= 0 && $files[$#files] =~ /(\d{6})$/ )
        {
            $cqtannum = sprintf( "%06d", $1+1 ); # take last num & inc
        }
    }
                                                # rtn formatted date str & ctr
    return( sprintf( "%sn%06d", $datestr, $cqtannum ) );
}


###########################################################################
#   NAME: CtrlC
#   DESC: what to do on a ^C
#   ARGS: n/a
#   RTNS: n/a
###########################################################################
sub CtrlC
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    CqSvr::GenSvrLog( $logdir, $CqSvr::lfile, {status => 'warning'}, 'Interrupt detected.  Stopping...' );
    print( "\n$cmdhdr (PID:$$) stopped ", CqSvr::ShortDateNTime(), "\n" );
    exit( $exitval );
}


###########################################################################
#   NAME: ReadCmd
#   DESC: perform the commands passed by the client
#   ARGS: socket fh, client host, client ip, client port, cqtan, cq/xml command
#   RTNS: n/a
###########################################################################
sub ReadCmd
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $socketfh = $_[0];                       # socket filehandle to prn to
    my $chost = $_[1];                          # client hostname
    my $cip = $_[2];                            # client ip
    my $cport = $_[3];                          # client port
    my $cqtan = $_[4];                          # cq transaction number
    my $cmd = $_[5];                            # save clean arg as cmd
    my $xmldoc = XML::Mini::Document->new();    # create XML parse obj
    my %xmlhash = ();                           # XML parse obj as hash
    my @xmlrtn = ();                            # init status in process rtn
    my $err = '';                               # err str rtn'd from funcs
    my $cmdstatus = '';                         # command status

    ($err, $cmd) = CqXml::PrelimXmlChk( $cmd ); # chk if well-formed XML
    if ( $err )                                 # not well-formed
    {
                                                # return err to user & log
        PrnRtnXml( $socketfh, '', '', $cqtan, $chost, $cip, $err );
        return();                               # get out'a here
    }

                                                # if write queue file err
    if ( $err = WriteQueueFile( $cqtan, $chost, $cip, $cmd ) )
    {
                                                # return err to user & log
        PrnRtnXml( $socketfh, '', '', $cqtan, $chost, $cip, $err );
        return();                               # get out'a here
    }

    print( "$dbghdr \$xmldoc->parse( \$cmd )...\n" ) if ( $debug );
                                                # now call the XML parser
    eval{ $xmldoc->parse( $cmd ); %xmlhash = %{${$xmldoc->toHash()}{$CqSvr::rootelem}} };
    if ( $@ || !%xmlhash )                      # if the parser failed
    {
        $err = 'unable to parse XML';           # here's our err message
                                                # rtn err to client & log
        PrnRtnXml( $socketfh, '', '', $cqtan, $chost, $cip, $err );
        return();                               # get out'a here
    }
                                                # tell user queued cmds are q'd
    $cmdstatus = PrnQdStat( CqXml::ReStructElems( 'no', $cip, %xmlhash ) );
                                                # break xml into exec cmds
    ($err, @xmlrtn) = CqXml::ReStructElems( 'yes', $cip, %xmlhash );
    $cmdstatus .= $err;                         # save errors to status
                                                # exec non-q'd & save status str
    $cmdstatus .= (CqXml::CqExecXml( $cqtan, @xmlrtn ))[0] if ( $#xmlrtn > 0 );

                                                # prn rtn status to client & log
    PrnRtnXml( $socketfh, ${$xmlrtn[0]}{db}, ${$xmlrtn[0]}{login}, $cqtan, $chost, $cip, $cmdstatus );
}


###########################################################################
#   NAME: WriteQueueFile
#   DESC: takes the XML/CQ commands and copies them to a queue file
#   ARGS: formatted cqtan num, hostname, ip, XML cmd
#   RTNS: err msg on err
###########################################################################
sub WriteQueueFile
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $cqtan = $_[0];                          # cq transaction number
    my $chost = $_[1];                          # client host
    my $cip   = $_[2];                          # client ip
    my $cmd   = $_[3];                          # xml/cq command
    my $rtn   = '';                             # default to ok return

                                                # if open queue file ok
    if ( open( QFILE, ">$logdir/$CqSvr::ipqfile$cqtan" ) )
    {
                                                # insert cqtan into CQ elem
        $cmd =~ s/^(<$CqSvr::rootelem )/$1 cqtan='$cqtan' /;
        print( QFILE $cmd );                    # print xml cmd to queue file
        print( QFILE "<$CqSvr::commroot client='$chost' ip='$cip'/>" );
        close( QFILE );                         # close the queue file
    }
    else                                        # if open failed
    {
                                                # prn err to STDERR
        warn( "$wrnhdr unable to write to '$logdir/$CqSvr::ipqfile$cqtan'!" );
        $rtn = "Unable to enqueue '$cqtan'!";   # set rtn to err str
    }

    return( $rtn );                             # return pass/fail
}


###########################################################################
#   NAME: PrnQdStat
#   DESC: prints queued status of records added to queue
#   ARGS: CqXml::ReStructElems() return (err, mod, dbinfo, array of rec hashes)
#   RTNS: string to prn to return socket
###########################################################################
sub PrnQdStat
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $err = shift( @_ );                      # error message?
    my $dbinfo = shift( @_ );                   # db info (which we don't need)
    my @xml = @_;                               # array of record hashes
    my %recatrb = ();                           # rec attributes hash
    my $rtn = '';                               # return string

    foreach $recref ( @xml )                    # go thru records
    {
                                                # save off attributes
        %recatrb = %{${$recref}{$CqSvr::atrbkey}};
                                                # gen XML rtn str
        $rtn .= "$CqSvr::rtnleadspc<$recatrb{rectype} ";
        $rtn .= "$CqSvr::recuk{$recatrb{rectype}}='$recatrb{key}' ";

        $rtn .= "action='$recatrb{action}' " if ( defined( $recatrb{action} ) );
        if ( $err )                             # if error condition
        {
            $err =~ s/&/&amp;/g;                # fix XML-entity &
            $err =~ s/</&lt;/g;                 # fix XML-entity <
            $rtn .= "status='error'>$err</$recatrb{rectype}>\n";
        }
        else                                    # queued ok
        {
            $rtn .= "status='queued'/>\n";      # say so
        }
    }

    return( $rtn );                             # print queued status
}


###########################################################################
#   NAME: PrnRtnXml
#   DESC: prn rtn status XML to socket, write live log, rename queue file
#   ARGS: socket filehandle, db, login, cqtan, client, ip, rtn xml str
#   RTNS: n/a
###########################################################################
sub PrnRtnXml
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $socket = $_[0];                         # socket filehandle
    my $db = $_[1] ? $_[1] : '';                # database
    my $login = $_[2] ? $_[2] : '';             # cq login
    my $cqtan = $_[3];                          # cq transaction number
    my $client = $_[4];                         # client name
    my $ip = $_[5];                             # client ip
    my $xml = $_[6];                            # xml cmd

#TODO - could this potentially be moved to CqSvr::Log2Xml()?
                                                # print sys msg if exist
    print( $socket "$CqSvr::sysmsg\n" ) if ( $CqSvr::sysmsg );
                                                # prn <ClearQuest> root element
    print( $socket "<$CqSvr::rootelem db='$db' login='$login' cqtan='$cqtan' client='$client' ip='$ip'>\n" );
    print( $socket "$xml" );                    # print XML rtn str
    print( $socket "</$CqSvr::rootelem>" );     # print magic end tag

                                                # open live log file
    if ( open( LIVELOG, ">$logdir/$CqSvr::lfile$cqtan" ) )
    {
                                                # write pretty XML to live log
        #CqSvr::Log2Xml( \*LIVELOG, $cqtan, {db => $db, login => $login, client => $client, ip => $ip}, "<![CDATA[$xml]]>" );
        CqSvr::Log2Xml( \*LIVELOG, $cqtan, {db => $db, login => $login, client => $client, ip => $ip}, "$xml" );
        close( LIVELOG );                       # close live log

                                                # rename in-progress q to q file
        if ( -f "$logdir/$CqSvr::ipqfile$cqtan" && !rename( "$logdir/$CqSvr::ipqfile$cqtan", "$logdir/$CqSvr::qfile$cqtan" ) )
        {
            warn( "$errhdr unable to rename queue file to '$logdir/$CqSvr::qfile$cqtan'!\n" );
        }
    }
    else                                        # open live log failed
    {
        warn( "$errhdr unable to write live log file '$logdir/$CqSvr::lfile$cqtan'!\n" );
    }
}
