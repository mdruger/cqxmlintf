#!/usr/bin/perl -w
###########################################################################
#   NAME: xmlstats.pl
#   DESC: dumps a bunch of stats for end of month/quarter/etc reports
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
use Net::LDAP;                                  # LDAP for looking up divisions
require( 'xmlstats.pm' );                       # frequently-changed variables
$| = 1;                                         # don't buffer output

###########################################################################
#   user globals
###########################################################################
my $back = 30;                                  # how many days back to look
my $output = '';                                # output file
my $logtype = 'live';                           # types of logs to search for
my $src = '//netshare/cqxmllogs';                 # log source directory
my $verbose = 0;                                # default: quietish

###########################################################################
#   static globals
###########################################################################
my $filehdr = 'cqxi_';                          # file name start
my $filetail = '.xml';                          # file name end
my $cmdhdr = $0; $cmdhdr =~ s,^.*[/\\],,;       # basename
my $errhdr = "$cmdhdr: ERROR -";                # err header
my $wrnhdr = "$cmdhdr: WARNING -";              # warning header
my $wrnspc = $wrnhdr; $wrnspc =~ tr/!/ /c;      # warning spacer
my $ldapsvr = 'mailsvr.site';           # LDAP server

###########################################################################
#   dynamic globals
###########################################################################
my $exitval = 0;                                # default exit = ok
                                                # date strings
my $yr  = sprintf( "%02d", (gmtime( time() ))[5] - 100 );
my $day = sprintf( "%03d", (gmtime( time() ))[7] );
my $stopyr = '';                                # yr X days ago
my $stopday = '';                               # day of yr X days ago
my @files = ();                                 # xml log file list
my %stats = ();                                 # data parsed from xml logs
my $div = undef;                                # division hash-ref
my $site = undef;                               # site hash-ref


###########################################################################
#   main()
###########################################################################
ParseCmd( @ARGV );                              # parse command line
print( "Searching logs from the last $back days...\n" );
                                                # calc X days back
($stopyr, $stopday) = CalcStopDate( $yr, $day, $back );
print( "From '$yr$day' to '$stopyr$stopday': " );
                                                # gen list of files to parse
@files = GenFileList( $src, $yr, $day, $stopyr, $stopday );
print( $#files+1, " files found\n" );
%stats = ParseFiles( @files );                  # read files into hash
($div, $site) = FindUsrInfo( %stats );          # derive div & site from users
PrnStats( $output, $div, $site, %stats );       # prn it all out


###########################################################################
#   NAME: ParseCmd
#   DESC: parses the command line
#   ARGS: @ARGV
#   RTNS: n/a (may set $back, $src, $logtype)
###########################################################################
sub ParseCmd
{
    my @args = @_;                              # save input locally

    for ( my $i=0; defined( $args[$i] ); $i++ ) # go thru input args
    {
        if ( $args[$i] =~ /^-h/o )              # help
        {
            select( STDERR ) if ( $exitval );   # prn to ERR if err condition
            print( "USAGE: $cmdhdr [-d <days>|-h|-o <file>|+q|-q|-s <src>|-v]\n" );
            print( "\t-d <days>  how many days back to examine (default: $back)\n" );
            print( "\t-h         this help screen\n" );
            print( "\t-o <file>  save output to file <file>\n" );
            print( "\t+q         look in queue logs and live logs\n" );
            print( "\t-q         only look in queue logs\n" );
            print( "\t-s <src>   alternate source directory (default: $src)\n" );
            print( "\t-v         verbose output\n" );
            exit( $exitval );
        }
        elsif ( $args[$i] =~ /^-d/o )           # days back
        {
            if ( $args[++$i] =~ /^\d+$/ )       # is next arg a number?
            {
                $back = $args[$i];              # next arg is days back
            }
            else                                # days arg ! a number
            {
                warn( "$errhdr invalid \"days\" argument '$args[$i]'!\n" );
                $exitval = 1;                   # set bad exit
                ParseCmd( '-h' );               # prn help & exit
            }
        }
        elsif ( $args[$i] =~ /^-o/o )           # output to file
        {
            $output = $args[++$i];              # next arg is output file
            if ( -s "$output" )                 # file exists & >0 in size
            {
                warn( "$errhdr output file '$output' already exists!\n" );
                $exitval = 1;                   # set bad exit
                ParseCmd( '-h' );               # prn help & exit
            }
        }
        elsif ( $args[$i] =~ /^\+q/o )          # add queue logs
        {
            $logtype = 'both';                  # chg log search type
        }
        elsif ( $args[$i] =~ /^-q/o )           # add queue logs
        {
            $logtype = 'queued';                # chg log search type
        }
        elsif ( $args[$i] =~ /^-s/o )           # alt src dir
        {
            $src = $args[++$i];                 # next arg is src dir
        }
        elsif ( $args[$i] =~ /^-v/o )           # verbose
        {
            $verbose = 1;                       # set verbose flag
        }
        else                                    # unknown arg
        {
            warn( "$errhdr unknown argument '$args[$i]'!\n" );
            $exitval = 1;                       # set bad exit
            ParseCmd( '-h' );                   # prn help & exit
        }
    }
}


###########################################################################
#   NAME: CalcStopDate
#   DESC: calculate the date X days ago
#   ARGS: cur yr, cur day, days back
#   RTNS: yr, day - X days back
###########################################################################
sub CalcStopDate
{
    my $stopyr = $_[0];                         # assume cur yr as stop year
    my $stopday = $_[1] - $_[2];                # stop day = cur day - days back

    if ( $stopday < 0 )                         # if looking back too far
    {
        $stopyr--;                              # go to last year
        $stopday += 366;                        # days/yr - day back + today
    }
                                                # rtn yr & day
    return( sprintf( "%02d", $stopyr ), sprintf( "%03d", $stopday ) );
}


###########################################################################
#   NAME: GenFileList
#   DESC: create a list of files to parse based on the dates
#   ARGS: src dir, cur yr, cur day, stop yr, stop day
#   RTNS: list of files to open & parse
###########################################################################
sub GenFileList
{
    my $dir    = $_[0];                         # source directory
    my $begyr  = $_[1];                         # current year
    my $begday = $_[2];                         # current day
    my $endyr  = $_[3];                         # yr, X days ago
    my $endday = $_[4];                         # day, X days ago
    my @rtn    = ();                            # init rtn array

                                                # while we haven't gone too far
    while ( $begday >= $endday && $begyr >= $endyr )
    {
                                                # if file exists, add to array
        push( @rtn, "$dir/${filehdr}l$begyr$begday$filetail" )
          if ( ($logtype eq 'live' || $logtype eq 'both') && -f "$dir/${filehdr}l$begyr$begday$filetail" );
        push( @rtn, "$dir/${filehdr}q$begyr$begday$filetail" )
          if ( ($logtype eq 'queued' || $logtype eq 'both') && -f "$dir/${filehdr}q$begyr$begday$filetail" );

        $begday = sprintf( "%03d", $begday-1 ); # go back 1 day
        if ( $begday < 0 )                      # if went back too far
        {
                                                # go back 1 yr
            $begyr = sprintf( "%02d", $begyr-1 );
            $begday = 366;                      # start from end of yr
        }
    }

    return( @rtn );                             # return file list
}


###########################################################################
#   NAME: ParseFiles
#   DESC: open the log files and look for connections, users, etc
#   ARGS: file list
#   RTNS: hash (date=>user=>action=>count)
###########################################################################
sub ParseFiles
{
    my @files = @_;                             # files to open & parse
    my $date = '';                              # date of file
    my $curusr = '';                            # interface user
    my %rtn = ();                               # init rtn array

    print( "$cmdhdr - reading log files...\n" ) if ( $verbose );
    foreach $file ( @files )                    # go thru files
    {
        $file =~ m|([^/\\]+)$|iog;              # get filename - path
        printf( "\t%15s %10db... ", $1, -s $file ) if ( $verbose );
        if ( open( FH, "<$file" ) )             # if open ok
        {
                                                # parse filename
            $file =~ /$filehdr[lq](\d+)$filetail/;
            $date = $1;                         # save date
            $curusr = '';                       # re-init current user
            while ( defined( $line = <FH> ) )   # read file
            {
                                                # if connection found
                if ( $line =~ / login='([^']+)'/ )
                {
                    $curusr = $1;               # save user
                }
                                                # if action found
                if ( $line =~ / action='([^']+)'/ )
                {
                                                # save action name & inc ctr
                    ${$rtn{$date}{$curusr}}{$1}++;
                }
                                                # if record w/ no action
                elsif ( $line =~ /<defect id=/ )
                {
                                                # must be a view
                    ${$rtn{$date}{$curusr}}{'view'}++;
                }
                                                # query
                elsif ( $line =~ /<query name=/ )
                {
                    ${$rtn{$date}{$curusr}}{'query'}++;
                }
            }
            close( FH );                        # close the log file
        }
        print( "done\n" ) if ( $verbose );
    }

    return( %rtn );                             # rtn nasty data structure
}


###########################################################################
#   NAME: FindUsrInfo
#   DESC: use LDAP to lookup user division & site
#   ARGS: big xml info hash
#   RTNS: ref to div hash (usr=>div), ref to site hash (usr=>site)
###########################################################################
sub FindUsrInfo
{
    my %xmlinfo = @_;                           # save hash ball
    my %users = ();                             # init usr tmp hash
    my $ldap = undef;                           # ldap obj
    my $msg = undef;                            # ldap message obj
    my %div = ();                               # init div rtn hash
    my %site = ();                              # init site rtn hash

    print( "$cmdhdr - looking up users in LDAP...\n" ) if ( $verbose );
    foreach $date ( keys( %xmlinfo ) )          # go thru ea day
    {
                                                # go thru ea usr/day
        foreach $usr ( keys( %{$xmlinfo{$date}} ) )
        {
            $users{$usr} = 1;                   # save user
        }
    }

    if ( $ldap = Net::LDAP->new( $ldapsvr ) )   # if ldap connection successful
    {
        $msg = $ldap->bind;                     # login to ldap server
        foreach $usr ( keys( %users ) )         # go thru users
        {
            $mailusr = "$usr\@mentor.com";      # append domain & find user
            $msg = $ldap->search( base => '#fix',
                                  scope => 'sub',
                                  filter => "mail=$mailusr" );
            if ( $msg->count < 1 )              # if nothing found
            {
                $div{$usr} = $site{$usr} = 'unknown';
            }
            else                                # if user found
            {
                foreach $entry ( $msg->entries ) # should only be 1 but oh well
                {
                                                # pull div
                    $div{$usr} = $entry->get_value( 'department' );
                                                # convert div to short name
                    $div{$usr} = $XmlStats::divs{$div{$usr}} if ( defined( $XmlStats::divs{$div{$usr}} ) );
                                                # pull site
                    $site{$usr} = $entry->get_value( 'site' );
                                                # if user is off site
                    if ( $site{$usr} eq 'Off-Site' )
                    {
                                                # get city
                        $site{$usr} = $entry->get_value( city );
                                                # get country
                        $site{$usr} .= '/' . $entry->get_value( country );
                    }
                    else                        # on-site
                    {
                        $site{$usr} =~ s/-.*$//; # rm specific office number
                    }
                }
            }
        }
    }
    else                                        # ldap connection failed
    {
        foreach $usr ( keys( %users ) )         # go thru users
        {
                                                # just finish
            $div{$usr} = $site{$usr} = 'unknown';
        }
    }

    $ldap->unbind;                              # logout
    $ldap->disconnect;                          # disconnect from ldap server

    return( \%div, \%site );                    # rtn refs to div & site
}


###########################################################################
#   NAME: PrnStats
#   DESC: prints all the stats
#   ARGS: output file, div hash-ref, site hash-ref, xml info hash ball
#   RTNS: n/a
###########################################################################
sub PrnStats
{
    my $outfile = shift( @_ );                  # output file to write to
    my %div = %{shift( @_ )};                   # de-ref div hash & save
    my %site = %{shift( @_ )};                  # de-ref site hash & save
    my %stats = @_;                             # xml usage info
    my $datestr = '';                           # init date string
    my $prnstr1 = "  %5.5s %-18.18s %-15.15s %-5.5s ";
    my $prnstr2 = "%4s %4s %4s %4s %4s %5s";    # std prn formatting
    my %usrctr = ();                            # counting users
    my %curctr = ();                            # counting user actions
                                                # counting all actions
    my %actctr = ( view => 0, query => 0, submit => 0, modify => 0, update => 0 );
    my %divctr = ();                            # counting divs
    my %grpctr = ();                            # counting groups
    my %sitectr = ();                           # counting sites
    my $udttl = 0;                              # user/day action total
    my $updctr = 0;                             # update action counter
    my $allttl = 0;                             # full total
    my @days = ();                              # for counting days
    my @users = ();                             # for counting users
    my @divs = ();                              # for counting divisions
    my @grps = ();                              # for counting groups
    my @sites = ();                             # for counting sites

    print( "$cmdhdr - writing output file '$outfile'...\n" ) if ( $verbose );
    if ( $outfile )                             # if output file defined
    {
        if ( open( OUTFH, ">$outfile" ) )       # if open succeeded
        {
            select( OUTFH );                    # default write to output file
        }
        else                                    # open failed
        {
            warn( "$wrnhdr unable to write to output file '$outfile'!\n" );
            warn( "$wrnspc Did you want to write to STDOUT instead? [Y/q]: " );
            chomp( $answer = <STDIN> );         # read user response
            if ( $answer eq 'q' )               # if user chose quit
            {
                die( "$errhdr operation aborted by user!\n" );
            }
        }
    }

    printf( "$prnstr1", 'DATE', 'USER', 'DIVISION', 'SITE' );
    printf( "$prnstr2\n", 'VIEW', 'QURY', 'SUB', 'MOD', 'UPD', 'TOTAL' );
    print( '-'x79, "\n" );                      # start printing totals
    foreach $date ( sort( keys( %stats ) ) )    # go thru xml usage hash by date
    {
        $datestr = $date;                       # save date str
                                                # go thru users per day
        foreach $user ( sort( keys( %{$stats{$date}} ) ) )
        {
            $usrctr{$user} = 1;                 # add user to list
                                                # prn date, usr, div, site
            printf( "$prnstr1", $datestr, $user, $div{$user}, $site{$user} );
            if ( $div{$user} ne 'unknown' )     # 
            {
                $grpctr{$div{$user}} = 1;
                                                # add div to list
                $divctr{$1} = 1 if ( $div{$user} =~ m#^([^/]+)/# );
            }
#warn( "$div{$user}\n\t", join( '  ', keys( %divctr ) ), "\n\t", join( '  ', keys( %grpctr ) ), "\n" );
                                                # add site to list
            $sitectr{$site{$user}} = 1 if ( $site{$user} ne 'unknown' );
            %curctr = ( view => 0, query => 0, submit => 0, modify => 0, update => 0 );
                                                # go thru actions per usr/day
            foreach $act ( sort( keys( %{$stats{$date}{$user}} ) ) )
            {
                                                # add act count to usr/day total
                $udttl += ${$stats{$date}{$user}}{$act};
                                                # if standard action
                if ( $act eq 'view' || $act eq 'query' || $act eq 'submit'
                     || $act eq 'modify' )
                {
                    $curctr{$act} = ${$stats{$date}{$user}}{$act};
                    $actctr{$act} += ${$stats{$date}{$user}}{$act};
                }
                else                            # CQ state transition
                {
                    $curctr{update} = ${$stats{$date}{$user}}{$act};
                    $actctr{update} += ${$stats{$date}{$user}}{$act};
                }
            }
            printf( "$prnstr2\n", $curctr{view}, $curctr{query},
              $curctr{submit}, $curctr{modify}, $curctr{update}, $udttl );
            $allttl += $udttl;                  # add to full total
            $udttl = 0;                         # re-init user/day total
            $datestr = '';                      # clear date string
        }
    }
    @days  = sort( keys( %stats ) );            # now sort & save uniq days
    @users = sort( keys( %usrctr ) );           #                      users
    @divs  = sort( keys( %divctr ) );           #                      divisions
    @grps  = sort( keys( %grpctr ) );           #                      groups
    @sites = sort( keys( %sitectr ) );          #                      sites
    print( '-'x79, "\n" );                      # start printing totals
    printf( "$prnstr1", $#days+1, $#users+1, $#divs+1, $#sites+1 );
    printf( "$prnstr2\n", $actctr{view}, $actctr{query}, $actctr{submit}, $actctr{modify}, $actctr{update}, $allttl );
    print( "\nTOTALS\n" );
    printf( "  Users     %4d - %s\n", $#users+1, join( ', ', @users ) );
    printf( "  Divs/Grps %4s - %s\n", ($#divs+1) . '/' . ($#grps+1), join( ', ', @grps ) );
    printf( "  Sites     %4d - %s\n", $#sites+1, join( ', ', @sites ) );
    printf( "  Actions   %4d\n", $allttl );
    printf( "    View    %4d\n", $actctr{view} );
    printf( "    Query   %4d\n", $actctr{query} );
    printf( "    Submit  %4d\n", $actctr{submit} );
    printf( "    Modify  %4d\n", $actctr{modify} );
    printf( "    Update  %4d (%d)\n", $actctr{update}, $actctr{modify}+$actctr{update} );
    if ( select() eq 'main::OUTFH' )            # we're writing to a file
    {
        select( STDOUT );                       # set default FH back to STDOUT
        close( OUTFH );                         # close the filehandle
    }
}
