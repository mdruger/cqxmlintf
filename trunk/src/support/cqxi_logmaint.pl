#!/usr/bin/perl -w
###########################################################################
#   NAME: cqxi_logmaint.pl
#   DESC: maintains the log files - rm old output logs, chk status of current
#   ARGS: n/a
#   RTNS: prn to STDERR if server process dead
###########################################################################
#   Copyright 2008 Mentor Graphics Corporation
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
# - clean output logs
# - log reqs & cln/day
# - chk tmp logs
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
    $libdir =~ s|\\|/|og;                       # convert \ -> /
}
local $cmdspc = $cmdhdr; $cmdspc =~ tr/!/ /c;   # command spacer
local $errhdr = "$cmdhdr: ERROR -";             # error header
local $errspc = $errhdr; $errspc =~ tr/!/ /c;   # error spacer
local $dbghdr = "$cmdhdr: DEBUG -";             # debug header

###########################################################################
#   Perl goo
###########################################################################
use lib "$libdir";                              # push startup dir to @INC
require( 'cqsvrvars.pm' );                      # server variables
require( 'prndbghdr.pm' );                      # print debug header

###########################################################################
#   globals
###########################################################################
my @gmtime   = gmtime( time() );                # time as array
                                                # 2-digit year
my $yr       = sprintf( "%02d", $gmtime[5]-100 );
my $day      = sprintf( "%03d", $gmtime[7] );   # day of the year
local $date  = gmtime( time() );                # save time as full str
      $date  =~ s/(\d{4})$/GMT $1/;             # insert "GMT" into date str
my $daysback = 10;                              # always keep 10 days back
my $rmdate   = '';                              # init rm cqtan date var
my $rmctr    = 0;                               # files removed counter
my $errctr   = 0;                               # file unlink errors counter
my $exitval  = 0;                               # default exit = ok
                                                # prevent warnings on 1-use vars
my @tmp      = ( $dbghdr, $CqSvr::debug, $CqSvr::loglinestr, $CqSvr::logtblhdr,);

###########################################################################
#   user configurable globals
###########################################################################
local $debug   = 0;                             # debug flag
local $prev    = 0;                             # search # prev days
local $verbose = 0;                             # verbose


###########################################################################
#   main()
###########################################################################
ParseCmd( @ARGV );                              # parse cmd line
if ( $prev <= 0 )                               # if just doing 10 days ago
{
    @yester = YesterDates( $yr, @gmtime );      # get yesterday's dates
                                                # get num of reqs from yesterday
    push( @yester, YesterReqs( "$CqSvr::fulllogdir/$CqSvr::arcdir", $yester[1] ) );
    LogYester( @yester );                       # write yesterday's info to log
                                                # calc 10 days ago's cqtan date
    $rmdate = CalcRmDate( $daysback, $yr, $day );
                                                # rm files from 10 days ago
    ($rmctr, $errctr) = ClnOutLogs( "$CqSvr::fulllogdir/$CqSvr::arcdir", $rmdate );
    LogResults( $rmdate, $rmctr, $errctr );     # save results of log cleaning
}
else
{
    while ( $prev > 0 )                         # while prevs to search
    {
        $rmdate = CalcRmDate( $daysback+$prev--, $yr, $day );
        print( "$cmdhdr: cleaning $rmdate..." );
        ($rmctr, $errctr) = ClnOutLogs( "$CqSvr::fulllogdir/$CqSvr::arcdir", $rmdate );
        print( " $rmctr files, $errctr errors\n" );
        LogResults( $rmdate, $rmctr, $errctr ); # save results of log cleaning
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

    for ( my $i=0; defined( $args[$i] ); $i++ ) # go thru args
    {
        if ( $args[$i] =~ /^-h/o )              # help requested
        {
            select( STDERR ) if ( $exitval );   # output to err if err set
            print( "USAGE: $cmdhdr [-d|-h|-p <#>|-v]\n" );
            print( "\t-d/ebug   run in debug mode\n" );
            print( "\t-h/elp    this help screen\n" );
            print( "\t-p/rev #  search previous # days before $daysback days ago\n" );
            print( "\t-v/erbose verbose output\n" );
            exit( $exitval );                   # get out'a here
        }
        elsif ( $args[$i] =~ /^-d/o )           # debug
        {
            $debug = $CqSvr::debug = 1;         # set global debug flag
        }
        elsif ( $args[$i] =~ /^-p/o )           # search prev
        {
            $prev = $args[++$i];                # next arg is # of days
            if ( $prev =~ /\D/ )                # if prev arg ! digit
            {
                $exitval++;                     # set bad exit, throw err
                warn( "$errhdr invalid number '$prev' specified with '-p' option!\n" );
                ParseCmd( '-h' );               # display help too
            }
        }
        elsif ( $args[$i] =~ /^-v/o )           # verbose enabled
        {
            $verbose = 1;                       # set global verbose flag
        }
        else                                    # unknown arg
        {
            $exitval++;                         # inc exit val
            warn( "$errhdr unknown argument '$args[$i]'!\n" );
            ParseCmd( '-h' );                   # display help too
        }
    }
}


###########################################################################
#   NAME: YesterDates
#   DESC: returns yesterday's date in several formats
#   ARGS: year (yy), gmtime()
#   RTNS: year (yy), cqtan (yyddd), date str (mm/dd)
###########################################################################
sub YesterDates
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my $yr    = shift( @_ );                    # current year (yy)
    my @time  = @_;                             # current time array
                                                # days per month
    my @dayspermon = qw( 31 28 31 30 31 30 31 31 30 31 30 31 );
    my $cqtan = CalcRmDate( 1, $yr, $time[7] ); # calc yesterday's cqtan date
    my $mon   = $time[4];                       # current month
    my $day   = $time[3];                       # current day

    if ( $time[3] == 1 )                        # 1st day of month
    {
        if ( $time[4] == 0 )                    # Janurary
        {
            $yr  = sprintf( "%02d", $yr-1 );    # last year
            $mon = 11;                          # December
            $day = 31;                          # last day of Dec
        }
        elsif ( $time[4] == 2 && !$yr%4 )       # Mar w/ leap yr
        {
            $mon = 1;                           # set mon = Feb
            $day = 29;                          # set day = leap day
        }
        else                                    # 1st day of some other month
        {
            $mon--;                             # go to prev mon
            $day = $dayspermon[$mon];           # last day of prev mon
        }
    }
    else                                        # not 1st day of the month
    {
        $day = $time[3]-1;                      # dec day
    }

    return( $yr, $cqtan, sprintf( "%02d/%02d", $mon+1, $day ) );
}


###########################################################################
#   NAME: YesterReqs
#   DESC: get num of requests from yesterday
#   ARGS: archive dir, yesterday's date
#   RTNS: num of reqs
###########################################################################
sub YesterReqs
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my $arcdir  = $_[0];                        # archive dir
    my $datesub = $_[1];                        # yesterday's cqtan date
    my @files   = ();                           # init file counter array

                                                # get list of files
    @files = <$arcdir/$datesub/$CqSvr::lfile${datesub}*>;
    return( $#files+1 );                        # return length of file list
}


###########################################################################
#   NAME: LogYester
#   DESC: writes yesterday's results to the log file
#   ARGS: yy, yyddd, mm/dd, #reqs
#   RTNS: 0 on success, 1 on error
###########################################################################
sub LogYester
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my $yr    = $_[0];                          # year
    my $cqtan = $_[1];                          # cqtan (yyddd)
    my $mmdd  = $_[2];                          # date in mm/dd
    my $reqs  = $_[3];                          # nu of reqs
                                                # logfile path
    my $logfile = "$CqSvr::statusfile$yr$CqSvr::statusext";
    my @read  = ();                             # init read array
    my $write = '';                             # init write str

    InitLog( $yr ) if ( ! -f "$logfile" );      # start new logfile if ! exist

    open( READ, "<$logfile" ) || return( 1 );   # read log file or return
    @read = <READ>;                             # read entire file into array
    close( READ );                              # close file

    foreach $line ( @read )                     # go thru log file
    {
        if ( $line =~ /$CqSvr::logupdstr/ )     # if "update" line
        {
                                                # add "update" (color-coded)
            $write .= "<span class='warn'>$CqSvr::logupdstr started - $main::date</span>\n";
        }
        elsif ( $line =~ /$CqSvr::logtblhdr/ )  # if table header row/line
        {
            $write .= $line;                    # save table header
            $write .= '<tr>';                   # insert new row of data
            $write .= "<td>$cqtan</td>";        # 
            $write .= "<td>$mmdd</td>";         # 
            $write .= "<td class='reqs'>$reqs</td><td>-</td></tr>\n";
        }
        else                                    # some other row
        {
            $write .= $line;                    # just save it
        }
    }

    open( WRITE, ">$logfile" ) || return( 1 );  # open log file for write | rtn
    print( WRITE $write );                      # write it out
    close( WRITE );                             # close log file

    return( 0 );                                # look'n good, rtn
}


###########################################################################
#   NAME: InitLog
#   DESC: creates a new log file
#   ARGS: year
#   RTNS: 0 on success, 1 on error
###########################################################################
sub InitLog
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my $yr      = $_[0];                        # save year
                                                # log file name
    my $logfile = "$CqSvr::statusfile$yr$CqSvr::statusext";

    open( WRITE, ">$logfile" ) || return( 1 );  # open log file for write | rtn
    print WRITE <<HTML;
<html>
<head>
WRITE
<title>CQ/XML Server Maintenance Status - 20$yr</title>
<style type='text/css'>
table   { border-collapse: collapse; }
td      { border: 1px solid #ccc; font-size: 80%; }
td.reqs { text-align: center; }
td, th  { padding: 2px 5px; }
th      { background-color: #ccc; border: 1px solid #aaa; }
h2      { margin-bottom: 5px; }
h4      { margin-top: 5px; }
.upd    { font-size: 80%; margin-bottom: 5px; }
.warn   { color: #f00; }
</style>
</head>
<body>
<h2>CQ/XML Server Maintenance Status - 20$yr</h2>
<div class='upd'>
<b>Updated:</b> $main::date
</div>
<table>
<tr><th>cqtan</th><th>cal</th><th>reqs</th><th>notes</th></tr>
</table>
</body>
</html>
HTML
    close( WRITE );                             # close log file
    return( 0 );                                # rtn ok
}


###########################################################################
#   NAME: CalcRmDate
#   DESC: calculates the date to remove
#   ARGS: # days back, current year, current day
#   RTNS: rm date (yyddd)
###########################################################################
sub CalcRmDate
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my $rmdays = $_[0];                         # rm this many days back
    my $curyr  = $_[1];                         # current year
    my $curday = $_[2];                         # current day
    my $rtndate = '';                           # date str to return

    if ( $curday < $rmdays )                    # EOY rollover
    {
        $rtndate = sprintf( "%02d", $curyr-1 ); # last year
        $rtndate .= sprintf( "%03d", $rtndate%4 # adjust day based on leap year
                                     ? 364-$rmdays+$curday+1 
                                     : 365-$rmdays+$curday+1 );
    }
    else                                        # middle of the year
    {
                                                # yyddd
        $rtndate = sprintf( "%02d%03d", $curyr, $curday-$rmdays );
    }

    return( $rtndate );                         # return yyddd
}


###########################################################################
#   NAME: ClnOutLogs
#   DESC: cleans out the logs
#   ARGS: archive dir, cqtan date (yyddd)
#   RTNS: # files removed, # errors
###########################################################################
sub ClnOutLogs
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my $arcdir  = $_[0];                        # archive dir
    my $datesub = $_[1];                        # cqtan date
    my $rmctr   = 0;                            # init remove counter
    my $errctr  = 0;                            # init error counter

                                                # go thru list of live tmp files
    #foreach $file ( <$arcdir/$datesub/$CqSvr::lfile${datesub}*> )
    foreach $file ( <$arcdir/$datesub/$CqSvr::lfile*> )
    {
        print( "$file" ) if ( $verbose );       # if verbose, prn file name
        if ( unlink( $file ) )                  # rm file
        {
            $rmctr++;                           # inc rm counter
        }
        else                                    # unlink/rm failed
        {
            print( " error" ) if ( $verbose );  # if verbose, prn 'error'
            $errctr++;                          # inc err counter
        }
        print( "\n" ) if ( $verbose );          # 
    }

    return( $rmctr, $errctr );                  # return rm counter, err counter
}


###########################################################################
#   NAME: LogResults
#   DESC: inserts # files rm'd into log file
#   ARGS: date to clean, rm'd counter, err counter
#   RTNS: 0 on success, 1 on error
###########################################################################
sub LogResults
{
    PDH::PrnDbgHdr( @_ ) if ( $debug );         # print debug info if requested

    my $rmdate  = $_[0];                        # cqtan rm date
    my $rmctr   = $_[1];                        # rm counter
    my $errctr  = $_[2];                        # err counter
    my $logfile = $CqSvr::statusfile;           # output file
       $rmdate  =~ /^(\d\d)/;                   # get yr
       $logfile .= "$1$CqSvr::statusext";       # make full file nae
    my @read    = ();                           # init read array
    my $write   = '';                           # init write scalar
    my @errmsg  = ();                           # init err msg

    push( @errmsg, "$errctr errors during log removal" ) if ( $errctr );

    open( FH, "<$logfile" ) || return( 1 );     # read log file or bail
    @read = <FH>;                               # read file
    close( FH );                                # done reading

    foreach $line ( @read )                     # go thru file
    {
        if ( $line =~ /$CqSvr::logupdstr/ )     # "Updated:" string
        {
                                                # put new date in update str
            $write .= "$CqSvr::logupdstr $main::date\n";
        }
                                                # if line ~ str & dates match
        elsif ( $line =~ m#$CqSvr::loglinestr# && $2 eq $rmdate )
        {
            $write .= $1;                       # write 1st 3 cells

                                                # save err if other than '-'
            unshift( @errmsg, $5 ) if ( $5 ne '-' );
                                                # if #reqs != # rm'd
            push( @errmsg, "$rmctr logs removed" ) if ( $4 != $rmctr );

            $write .= @errmsg                   # if err msg, format
                      ? "<td class='warn'>" . join( '<br>', @errmsg ) . "</td></tr>\n"
                      : "<td>-</td></tr>\n";
            @errmsg = ();                       # re-init errmsg
        }
        else                                    # normal line
        {
            $write .= $line;                    # just print it
        }
    }

    open( WRITE, ">$logfile" ) || return( 1 );  # open log file for write
    print( WRITE $write );                      # dump
    close( WRITE );                             # close

    return( 0 );                                # return success
}
