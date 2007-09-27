#!/usr/bin/perl -w
###########################################################################
#   NAME: 
#   DESC: 
#   ARGS: 
#   RTNS: 
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
#   globals
###########################################################################
my $cmdhdr = $0; $cmdhdr =~ s/^.*[\/\\]([^\/\\]+)$/$1/;
my $errhdr = "$cmdhdr: ERROR -";                # 
my $exitval = 0;                                # 
my $dir = '.';
$| = 1;

my @logs = ();
my $logpre = 'cqxi';
my $argdate = '[0-9][0-9][0-9][0-9][0-9]';
my $qorlive = '?';


###########################################################################
#   main()
###########################################################################
ParseCmd( @ARGV );
print( 'Reading...' );
@logs = sort( <$dir/$logpre.${qorlive}_${argdate}n[0-9][0-9]*> );
print( " done\n" );
FindMissing( \@logs );


###########################################################################
#   NAME: ParseCmd
#   DESC: 
#   ARGS: 
#   RTNS: 
###########################################################################
sub ParseCmd
{
    my @args = @_;                              # 

    for ( my $i=0; defined( $args[$i] ); $i++ ) # go thru args
    {
        if ( $args[$i] =~ /^-h/o )              # -h
        {
            print( "USAGE: $cmdhdr [-f:<date>|-h|-ql:<q/l>] <dir>\n" );
            print( "\t-f:<date> filter for files from date\n" );
            print( "\t-h        this help screen\n" );
            print( "\t-ql:<q/l> only match [q]ueue files or [l]ive files\n" );
            print( "\tdir       directory to review\n" );
            exit( $exitval );                   # 
        }
        elsif ( $args[$i] =~ /^-f:(\d+)$/ )     # date filter
        {
            $argdate = $1;
        }
        elsif ( $args[$i] =~ /^-ql:([ql])$/ )   # queued or live
        {
            $qorlive = $1;
        }
        elsif ( -d $args[$i] )                  # if arg is dir
        {
            $dir = $args[$i];                   # 
        }
        else
        {
            warn( "$errhdr unknown argument '$args[$i]'!\n" );
            $exitval = 1;                       # set bad exit
            ParseCmd( '-h' );                   # get some help
        }
    }
}


###########################################################################
#   NAME: FindMissing
#   DESC: 
#   ARGS: ptr to log array
#   RTNS: 
###########################################################################
sub FindMissing
{
    my $logs = $_[0];                           # 
    my $date = '';
    my $ctr  = '';
    my $olddate = '';
    my $oldctr = '';

    for ( my $i=0; defined( ${$logs}[$i] ); $i++ )
    {
        ${$logs}[$i] =~ /$logpre.([ql]_\d{5})\w(\d{6})$/;
        $date = $1; $ctr = $2;
        if ( $date ne $olddate )
        {
            print( "\n$date\n" );
            $olddate = $date;
        }
        else
        {
            while ( $ctr != ++$oldctr )
            {
                printf( "  %06d", $oldctr );
            }
        }
        $oldctr = $ctr;
    }
}
