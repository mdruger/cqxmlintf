#!/usr/bin/perl
###########################################################################
#   NAME: cqsys.pm
#   DESC: system-level server functions
#   PKG:  CqSys
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
package CqSys;                                  # package name
require( 'cqsvrvars.pm' );                      # hard-coded svr locs/strs
                                                # set debug vars for this pkg
$errhdr = defined( $main::errhdr ) ? $main::errhdr : 'ERROR:';
$errspc = defined( $main::errspc ) ? $main::errspc : '      ';
$debug  = defined( $main::debug )  ? $main::debug  : 0;
$dbghdr = defined( $main::dbghdr ) ? $main::dbghdr : 'DEBUG:';


###########################################################################
#   NAME: PrnBinMailMsg
#   DESC: prints or mails msg
#   ARGS: msg, @{to}, subject, prn only, exit
#   RTNS: exit on err, else n/a
###########################################################################
sub PrnBinMailMsg
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $msg  = $_[0];                           # mail msg
    my @to   = @{$_[1]};                        # list to send mail to
    my $subj = $_[2];                           # mail subject
    my $prn  = $_[3];                           # prn or mail?
    my $exit = $_[4];                           # exit after mail/prn

    if ( $prn )                                 # if prn only
    {
        warn( "$errhdr $msg\n" );               # just prn msg
    }
                                                # open pipe to /bin/mail
    elsif ( !open( MAIL, "|/bin/mail -s '$subj' @to" ) )
    {
        warn( "$errhdr unable to send mail!\n" );
        warn( "$errspc this error was created by the condition:\n" );
        die(  "$errspc $msg\n" );
    }
    else                                        # mail pipe opened
    {
        print( MAIL "$msg" );                   # print message to mail pipe
        close( MAIL );                          # close mail pipe
    }

    exit( $exit ) if ( $exit );                 # exit if exit requested
}


###########################################################################
#   NAME: FindSvrProcs
#   DESC: find cq/xml server processes
#   ARGS: svr name, just search cur user procs?
#   RTNS: anon-array of errors, hash of pids (pid=>args)
###########################################################################
sub FindSvrProcs
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # pring debug info if requested

    my $svrname = $_[0];                        # live or queue svr?
    my $useronly = $_[1];                       # only look at this user's procs
    my @cmdfiles = ();                          # list of pid cmdline files
    my $proccmd = '';                           # cmd str
    my $pid = 0;                                # process id
    my @errrtn = ();                            # errors to return
    my %rtn = ();                               # rtn hash of pids

    return( [('process detection not enabled on Windows!')], %rtn ) if ( $CqSvr::osiswin );
    @cmdfiles = </proc/[0-9][0-9]*/cmdline>;
    return( [("can't read from /proc!")], %rtn ) if ( !@cmdfiles );
    foreach $file ( @cmdfiles )                 # go thru /proc/*/cmdline files
    {
                                                # skip if usr chk & proc != eUID
        next if ( $useronly && (stat( $file ))[4] != $> );
        print( "$dbghdr opening $file...\n" ) if ( $debug );
        $file =~ m#^/proc/(\d+)/cmdline$#;      # get pid num from filename
        $pid = $1;                              # save off the pid
        if ( !open( PROC, "<$file" ) )          # if problem opening
        {
                                                # add err msg
            push( @errrtn, "unable to open '$pid' process file!" );
        }
        else                                    # open ok
        {
            $proccmd = <PROC>;                  # cmd is only 1 line
            close( PROC );                      # close cmdline file
            next if ( !$proccmd );              # skip sys cmds w/o line

            print( "$dbghdr command = $proccmd\n" ) if ( $debug );
                                                # if cmd match & filename parse
            if ( $proccmd =~ m#^$CqSvr::execstrre.*\W$svrname(.*)# )
            {
                $rtn{$pid} = $1;                # save process arguments
                $rtn{$pid} =~ s/[^-\w]/ /og;    # rm funky chars out of cmd
            }
        }
    }

    return( [@errrtn], %rtn );                  # rtn errs & pids
}


###########################################################################
#   NAME: MatchSvrArgs
#   DESC: uses the port/sys args to match svr processes
#   ARGS: port offset, multi-sys, process hash
#   RTNS: matching pids
###########################################################################
sub MatchSvrArgs
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $run = shift( @_ );                      # run/port arg
    my $sys = shift( @_ );                      # multi-system arg
    my %procs = @_;                             # svr procs
    my @rtn = ();                               # return matching pids

    foreach $pid ( keys( %procs ) )             # go thru matching pids
    {
                                                # if no run & no run switch
        if ( (!$run && $procs{$pid} !~ /$CqSvr::runswitch/)
                                                # or run & run matched
             || ($run && $procs{$pid} =~ /$CqSvr::runswitch\s+$run(\D+.*)?$/) )
        {
                                                # if no multisys & no sys switch
            if ( (!$sys && $procs{$pid} !~ /$CqSvr::sysswitch/)
                                                # or multi-sys & sys arg
                 || ($sys && $procs{$pid} =~ /$CqSvr::sysswitch/) )
            {
                push( @rtn, $pid );             # add pid to rtn list
            }
        }
    }

    return( @rtn );                             # rtn matching pids
}


###########################################################################
#   NAME: MatchSvrPort
#   DESC: uses the port args to match svr processes
#   ARGS: port offset, process hash
#   RTNS: matching pid, 0 on fail
###########################################################################
sub MatchSvrPort
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $run = shift( @_ );                      # run/port arg
    my %procs = @_;                             # svr procs

    foreach $pid ( keys( %procs ) )             # go thru matching pids
    {
                                                # if no run & no run switch
        if ( (!$run && $procs{$pid} !~ /$CqSvr::runswitch/)
                                                # or run & run matched
             || ($run && $procs{$pid} =~ /$CqSvr::runswitch\s+$run(\D+.*)?$/) )
        {
            return( $pid );                     # rtn pid w/ match
        }
    }

    return( 0 );                                # rtn no matching pids
}


###########################################################################
#   NAME: PortInUse
#   DESC: checks that the passed port is in use
#   ARGS: port number
#   RTNS: 0 if available, 1 if in use
###########################################################################
sub PortInUse
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested
    use Socket;                                 # socket nirvana

    my $port = $_[0];                           # port number
                                                # create internet stream socket
    socket( PIUSOCKET, PF_INET, SOCK_STREAM, $CqSvr::tcpproto ) or return( 1 );
                                                # allow bind to port in use
    setsockopt( PIUSOCKET, SOL_SOCKET, SO_REUSEADDR, 1 ) or return( 1 );
                                                # bind server socket to address
    bind( PIUSOCKET, sockaddr_in( $port, INADDR_ANY ) ) or return( 1 );
    close( PIUSOCKET );                         # close this socket

    return( 0 );                                # return available
}
