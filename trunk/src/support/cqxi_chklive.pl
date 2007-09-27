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
require( 'cqsvrfuncs.pm' );                     # server functions
require( 'cqsys.pm' );                          # system-level functions

###########################################################################
#   globals
###########################################################################
my @passthru = ();                              # init pass-thru args
my $errs     = '';                              # errs from CqSys pkg
my %procs    = ();                              # server processes
my $portpid  = ();                              # pid on same port
my $node     = lc( hostname() );                # machine name
my $mailsubj = "$CqSvr::mailerrsubj on '$node'"; # mail subject
                                                # prevent warnings on 1-use vars
my @tmp      = ( $CqSvr::mailerrsubj, $CqSvr::cqperl,
                 $CqSvr::port, $CqSvr::cpenvlang, $CqSvr::licenv,
                 $CqSvr::debug, $CqSys::debug,
               );

###########################################################################
#   user configurable globals
###########################################################################
local $debug = 0;                               # debug flag
local $nomail = 0;                              # don't send mail
local $statall = 0;                             # status of all flag
local $useronly = 0;                            # user process flag
local $runnum = 0;                              # running on alt port?
local $multisys = 0;                            # multi-sys from same src


###########################################################################
#   main()
###########################################################################
@passthru = ParseCmd( @ARGV );                  # pull out debug & pass-thru
($errs, %procs) = CqSys::FindSvrProcs( "$CqSvr::livename", 0 );

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
                                                # match processes w/ port offset
$portpid = CqSys::MatchSvrPort( $runnum, %procs );

if ( !$portpid )                                # no matching procs found
{
    if ( @{$errs} )                             # errs from FindSvrProcs()
    {
        map( s/^(.*)$/$errhdr $1\n/, @{$errs} ); # slam errhdr on front of err
                                                # join errs & send via email
        CqSys::PrnBinMailMsg( 'ERROR: ' . join( '', @{$errs} ), \@CqSvr::mailerrto, $mailsubj, ($statall || $nomail), 1 );
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
            print( "USAGE: $cmdhdr [-d|(-)-h|-n|-p|$CqSvr::runswitch <#>|$CqSvr::sysswitch|-u|--*|*]\n" );
            print( "\t-d/ebug   run in debug mode\n" );
            print( "\t-h/elp    this help screen\n" );
            print( "\t-n/omail  don't send mail if error detected\n" );
            print( "\t-p/rint   just print running server processes\n" );
            print( "\t$CqSvr::runswitch/un #   run with alternate port/dir number added\n" );
            print( "\t$CqSvr::sysswitch/ys     run with multiple systems using same src\n" );
            print( "\t-u/ser    only look through current user's processes\n" );
            print( "\t--*/*     pass-through arguments\n" );
            exit( 0 );                          # get out'a here
        }
        elsif ( $args[$i] =~ /^-d/o )           # debug
        {
                                                # set global debug flag
            $debug = $CqSvr::debug = $CqSys::debug = 1;
        }
        elsif ( $args[$i] =~ /^-n/o )           # don't send mail on error
        {
            $nomail = 1;                        # set global no-mail flag
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
#   NAME: RestartSvr
#   DESC: restarts the cq/xml live server
#   ARGS: run/port num, pass-through args from cmd line
#   RTNS: n/a
###########################################################################
sub RestartSvr
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $port = $CqSvr::port + shift( @_ );      # port to chk
                                                # err msg to send
    my $mailmsg = 'server process not running! Restarting...';

    if ( CqSys::PortInUse( $port ) )            # if the port is in use
    {
        $mailmsg .= "\n$errhdr port in use.  Unable to restart!";

                                                # throw err (w/o restart)
        CqSys::PrnBinMailMsg( $mailmsg, \@CqSvr::mailerrto, $mailsubj, ($statall || $nomail), 1 );
    }
    else
    {
                                                # throw err
        CqSys::PrnBinMailMsg( $mailmsg, \@CqSvr::mailerrto, $mailsubj, ($statall || $nomail), 0 );
        $ENV{LANG} = $CqSvr::cpenvlang;         # explicitely set code page
        $ENV{LM_LICENSE_FILE} = $CqSvr::licenv; # set license servers trio
                                                # startup server w/ passthru
        exec( "$CqSvr::cqperl $cmddir/$CqSvr::livename @_"  );
    }
}
