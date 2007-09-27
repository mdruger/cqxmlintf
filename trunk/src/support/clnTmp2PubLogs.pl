#!/usr/bin/perl -w
###########################################################################
#   NAME: clnTmp2PubLogs.pl
#   DESC: cleans up any tmp logs that weren't written into the public logs
#   RTNS: number of errors encountered
###########################################################################
#   Copyright 2007 Mentor Graphics Corporation
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
require( 'cqsvrvars.pm' );                      # server variables
require( 'cqsvrfuncs.pm' );                     # server functions
$| = 1;                                         # don't buffer output
my @tmp = ( $CqSvr::rootelem );                 # hide "possible typo" warning


###########################################################################
#   user globals
###########################################################################
my $debug   = 0;                                # default: debug off
my $logtype = city;                              # default: live logs
my $verbose = 0;                                # default: not verbose
my $pub     = '';                               # public log dir
my $src     = '';                               # src/tmp log dir

###########################################################################
#   static globals
###########################################################################
local $cmdspc = $cmdhdr; $cmdspc =~ tr/!/ /c;   # basename spacing
local $errhdr = "$cmdhdr: ERROR -";             # error header
local $errspc = $errhdr; $errspc =~ tr/!/ /c;   # error header spacing
#local $dbghdr = "$cmdhdr: DEBUG -";             # debug header

###########################################################################
#   dynamic globals
###########################################################################
my $exitval = 0;                                # default: ok exit
my %loglist = ();                               # date=>[files] of tmp log files
my @arclogs = ();                               # tmp logs to archive


###########################################################################
#   main()
###########################################################################
($pub, $src) = ParseCmd( @ARGV );               # 
%loglist = GenLogList( $src );                  # 
                                                # 
($errs, @arclogs) = WriteLogs2Pub( $pub, %loglist );
$errs += ArchiveLogs( $src, @arclogs );         # 
exit( $errs );                                  # 


###########################################################################
#   NAME: ParseCmd
#   DESC: 
#   ARGS: 
#   RTNS: 
###########################################################################
sub ParseCmd
{
    my @args = @_;                              # 
    my $src = '';                               # 
    my $pub = '';                               # 

    for ( my $i=0; defined( $args[$i] ); $i++ ) # go thru args
    {
        if ( $args[$i] =~ /^-h/o )              # help
        {
            select( STDERR ) if ( $exitval );   # prn to ERR if err flagged
            print( "USAGE: $cmdhdr [-d|-dv|-h|-q] -p <pdir> -s <sdir>\n" );
            print( "\t-d/ebug       debug output\n" );
            print( "\t-dv/erbose    verbose debug output\n" );
            print( "\t-p/ub <pdir>  public log dir\n" );
            print( "\t-q/ueued      fix queued logs instead of live logs\n" );
            print( "\t-s/rc <sdir>  source log dir\n" );
            print( "\t-v/erbose     verbose output\n" );
            exit( $exitval );                   # exit
        }
        elsif ( $args[$i] =~ /^-dv/ )           # vebose debug
        {
            $debug = $CqSvr::debug = 2;         # 
        }
        elsif ( $args[$i] =~ /^-d/ )            # debug
        {
            $debug = $CqSvr::debug = 1;         # 
        }
        elsif ( $args[$i] =~ /^-p/ )            # public log dir
        {
            $pub = $args[++$i];                 # next arg is pub dir
        }
        elsif ( $args[$i] =~ /^-q/ )            # fix queued logs
        {
            $logtype = 'q';                     # chg global
        }
        elsif ( $args[$i] =~ /^-s/ )            # src log dir
        {
            $src = $args[++$i];                 # next arg is src dir
        }
        elsif ( $args[$i] =~ /^-v/ )            # 
        {
            $verbose = 1;                       # 
        }
        else                                    # unknown arg
        {
            warn( "$errhdr unknown argument '$args[$i]'!\n\n" );
            $exitval = 1;                       # set bad exit val
        }
    }

    if ( ! -d $pub )                            # bad pub dir
    {
        warn( "$errhdr invalid public log dir '$pub'!\n" );
        $exitval = 1;
    }
    if ( ! -d $src )                            # bad src dir
    {
        warn( "$errhdr invalid source log dir '$pub'!\n" );
        $exitval = 1;
    }
    elsif ( ! -d "$src/$CqSvr::arcdir" )        # no src archive dir
    {
        warn( "$errhdr source log dir does not have a '$CqSvr::arcdir' sub-directory!\n" );
        $exitval = 1;
    }
    ParseCmd( '-h' ) if ( $exitval );           # prn help & exit

    return( $pub, $src );
}


###########################################################################
#   NAME: GenLogList
#   DESC: read log dir & gens list of files to shove into pub logs
#   ARGS: tmp src log dir
#   RTNS: hash of arrays by date (date=>[files])
###########################################################################
sub GenLogList
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $src     = $_[0];                        # tmp log src dir
    my $fdate   = '';                           # file (cqtan) date
    my %loglist = ();                           # rtn hash
    my $total   = 0;                            # total files looked at
    my $keep    = 0;                            # files saved for processing
    my @time    = (gmtime( time() ))[5,7];      # save yr & yr-day
                                                # today in cqtan format
    my $today   = sprintf( "%02d%03d", $time[0]-100, $time[1] );

    print( "$cmdhdr: generating tmp log list...\n$cmdspc  DATE  FILE" ) if ( $verbose );
                                                # go thru log files in src
    foreach $file ( sort( <$src/${CqSvr::filepre}.${logtype}_[0-9][0-9][0-3][0-9][0-9][a-z]*> ) )
    {
        $total++;                               # count another file down
                                                # parse off date (yyddd)
        $file =~ m#^$src/${CqSvr::filepre}.${logtype}_(\d{5})[a-z]\d{6}$#;
        $fdate = $1;                            # save date
        print( "\n$cmdspc  $fdate $file" ) if ( $verbose );
        if ( $fdate eq $today )                 # if file date = today
        {
            print( ' (skipped)' ) if ( $verbose );
            next;                               # skip so don't collide w/ svr
        }
        $keep++;                                # inc keeper file counter

        push( @{$loglist{$fdate}}, $file );     # add file to array by date
    }
    print( "\n" ) if ( $verbose );              # 

    if ( $verbose )                             # some pretty output
    {
        print( "$cmdhdr: $total files reviewed\n" );
        print( "$cmdspc  $keep files flagged for processing\n" );
        print( "$cmdspc  ", scalar( keys( %loglist ) ), " dates covered\n" );
    }
    return( %loglist );                         # rtn date=>[files] hash
}


###########################################################################
#   NAME: WriteLogs2Pub
#   DESC: writes tmp logs 2 pub logs
#   ARGS: pub log dir, hash/array of tmp logs
#   RTNS: errors encountered, list of successfully updated tmp logs
###########################################################################
sub WriteLogs2Pub
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $pub     = shift( @_ );                  # save off public log dir
    my %tmplogs = @_;                           # list of tmp logs
    my $logfh   = undef;                        # pub log filehandle
    my @tmp2pub = ();                           # list of ok tmp logs
    my $errctr  = 0;                            # error counter

    print( "$cmdhdr: appending tmp logs to public logs...\n" ) if ( $verbose );
    foreach $date ( sort( keys( %tmplogs ) ) )  # go thru logs by date
    {
        print( "$cmdspc  ", $#{$tmplogs{$date}}+1, " logs to '${CqSvr::filepre}_${logtype}$date.xml'\n" ) if ( $verbose );
                                                # open pub log & move file ptr
        $logfh = CqSvr::OpenLog( "$pub/${CqSvr::filepre}_${logtype}$date.xml", 1 );
                                                # go thru tmp logs in order
        foreach $tmplog ( sort( @{$tmplogs{$date}} ) )
        {
            if ( open( TMPLOG, "<$tmplog" ) )   # open tmp log ok
            {
                                                # read log, line by painful line
                while ( defined( $line = <TMPLOG> ) )
                {
                    print( $logfh $line );      # append line to pub log file
                }
                close( TMPLOG );                # close tmp log, duh
                push( @tmp2pub, $tmplog );      # add to ok list
            }
            else                                # open failed!
            {
                warn( "$errhdr can't read from '$tmplog'!\n" );
                warn( "$errspc skipping the rest of '$date' log.\n" );
                $errctr++;                      # inc err ctr
                last;                           # skip the rest of these
            }
        }

        print( $logfh "</$CqSvr::rootelem>" );  # prn root elem close to log
        close( $logfh );                        # close pub log file
    }
    return( $errctr, @tmp2pub );                # rtn list of ok tmp logs
}


###########################################################################
#   NAME: ArchiveLogs
#   DESC: 
#   ARGS: 
#   RTNS: 
###########################################################################
sub ArchiveLogs
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $srcdir   = shift( @_ );                 # tmp log src dir
    my @tmplogs  = @_;                          # save tmp log filenames
    my $leafname = '';                          # file/leaf name
    my $fdate    = '';                          # file date
    my $errctr   = 0;                           # error counter

    print( "$cmdhdr: archiving tmp logs...\n" ) if ( $verbose );
    foreach $file ( @tmplogs )                  # go thru file list
    {
                                                # if filename is in known format
        if ( $file =~ /(${CqSvr::filepre}.${logtype}_(\d{5})\w\d{6})$/ )
        {
            $leafname = $1;                     # save file name
            $fdate = $2;                        # save file date
            print( "$cmdspc  $leafname -> $srcdir/$CqSvr::arcdir/$fdate\n" ) if ( $verbose );
                                                # mk src/arc/date dir if ! dir
            mkdir( "$srcdir/$CqSvr::arcdir/$fdate", 0700 ) if ( ! -d "$srcdir/$CqSvr::arcdir/$fdate" );
                                                # if rename failed
            if( !rename( "$file", "$srcdir/$CqSvr::arcdir/$fdate/$leafname" ) )
            {
                warn( "$errhdr unable to move '$file'!\n" );
                warn( "$errspc please move the file manually so it doesn't get logged again\n" );
                $errctr++;                      # inc err ctr
            }
        }
        else                                    # weird filename format
        {
            warn( "$errhdr unable to parse filename '$file'\n" );
            warn( "$errspc please move the file manually so it doesn't get logged again\n" );
            $errctr++;                          # inc err ctr
        }
    }

    return( $errctr );                          # return num of errs
}
