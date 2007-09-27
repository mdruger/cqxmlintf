#!/usr/bin/perl -w
###########################################################################
#   NAME: encstr.pl
#   DESC: takes a encryption key and some strs & encrypts the strs w/ RC4
#   ARGS: key, strings
#   RTNS: 0=success, 1=warning, 2+=error, STDOUT=encrypted strings
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
BEGIN { push( @INC, '..' ); }                   # RC4 is housed one dir up
use Crypt::RC4;                                 # encryption module

###########################################################################
#   global vars
###########################################################################
                                                # basename
my $cmdhdr = $0 =~ m,^.*[/\\]([^/\\]+)$,o ? $1 : $0;
my $cmdspc = $cmdhdr; $cmdspc =~ tr/!/ /c;      # basename spacer
my $encstr = '';                                # tmp var to hold enc'd str
my $rtn    = 0;                                 # init rtn = ok

###########################################################################
#   main()
###########################################################################
                                                # quick check for arg count
die( "USAGE: $cmdhdr <key> <str(s)>\n" ) if ( $#ARGV < 1 );
binmode( STDOUT );                              # this is gonna be junky
for ( my $i=1; defined( $ARGV[$i] ); $i++ )     # go thru args 2..
{
    $encstr = RC4( $ARGV[0], $ARGV[$i] );       # encrypt & save
    print( "$encstr\n" );                       # prn encrypted str to STDOUT
    if ( $encstr =~ />/ )                       # if > in output
    {
        warn( "\a$cmdhdr - ERROR: Output string contains a '>' character!\n" );
        warn( "$cmdspc          This will cause problems in the CQ/XML Interface.\n" );
        $rtn = 1 if ( $rtn < 1 );               # set warning return
    }
}
exit( $rtn );                                   # rtn success/warn/err
