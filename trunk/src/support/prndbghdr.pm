###########################################################################
#   NAME: prndbghdr.pm
#   DESC: print debug header info
#   PKG:  PDH
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
package PDH;  

###########################################################################
#   NAME: PrnDbgHdr
#   DESC: prints debug info
#   ARGS: args sent to calling function
#   RTNS: n/a - prints to STDOUT
###########################################################################
sub PrnDbgHdr
{
    my $debug  = defined( $main::debug )  ? $main::debug  : 0;
    my $dbghdr = defined( $main::dbghdr ) ? $main::dbghdr : 'DEBUG: ';

    print( $dbghdr, (caller( 1 ))[3] );         # print calling function
    if ( $debug <= 1 )                          # std debug output
    {
        print( '( ', defined( @_ ) ? join( ', ', @_ ) : '', " )...\n" );
    }
    else                                        # verbose debug output
    {
        print( "\n" );
        use Data::Dumper;                       # prn'ing complex data structs
        for ( my $i=0; defined( $_[$i] ); $i++ ) # go thru args
        {
            print( "\t$i: " );                  # prn arg num
                                                # Dumper(cmplx) else just prn
            print( ref( $_[$i] ) && ref( $_[$i] ) !~ /^CQ/ ? Dumper( $_[$i] ) : $_[$i], "\n" );
        }
    }
}

1;
