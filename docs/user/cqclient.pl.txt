#!/usr/bin/perl -w
###########################################################################
#   NAME: cqxmlclient.pl
#   DESC: opens a socket connection & sends a file through
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
my $server = 'cqtestxml';                # cq server
my $port   = 5556;                              # cq server listening port
my $eof    = '</ClearQuest>';                   # end of data tag
                                                # exec name, exec dir
my ($cmdhdr, $cmddir) = ($0 =~ m|^(.*)[/\\]([^/\\]+)$|o) ? ($2, $1) : ($0, '.');
my $errhdr = "\a$cmdhdr: ERROR -";              # error header
my $errspc = $errhdr; $errspc =~ tr/!/ /c;      # error header spacing
my $dbghdr = "$cmdhdr: DEBUG -";                # debug header
my $exitval = 0;                                # exit val (default = 0)
my $cmd = '';                                   # command
my @svrout = ();                                # server output
my $debug = 0;                                  # debug flag
my @files = ();                                 # files to work with
my $shutdown = 1;                               # client shutdown enabled


###########################################################################
#   Perl goo
###########################################################################
require 5.006;                                  # need this rev for sockets
$| = 1;                                         # don't buffer output
use FileHandle;                                 # autoflush as method
use Socket;                                     # socket io


###########################################################################
#   main()
###########################################################################
ParseCmd( @ARGV );                              # parse the command line

foreach $file ( @files )                        # foreach file in cmd list
{
    @svrout = SendFile( $file );                # send file through pipe
    print( "@svrout\n" ) if ( @svrout );        # prn output from pipe
}

exit( $exitval );                               # exit


###########################################################################
#   NAME: ParseCmd
#   DESC: parses the command line
#   ARGS: @ARGV (or '-h' on err)
#   RTNS: 
###########################################################################
sub ParseCmd
{
    my @args = @_;                              # save arguments

    for ( my $i=0; defined( $args[$i] ); $i++ ) # go thru args
    {
        if ( $args[$i] =~ /^-h/o )              # if help requested
        {
            select( STDERR ) if ( $exitval );   # prn to ERR if err flagged
                                                # prn usage
            print( "USAGE: $cmdhdr [-d|-h|-n|-p <(+)#>|-s <svr>] [-f] <file(s)>\n" );
            print( "        -d/ebug          enable debug mode\n" );
            print( "        -f/ile <file(s)> file(s) to send to server\n" );
            print( "        -n/oclose        don't close socket after sending\n" );
            print( "        -h/elp           this help screen\n" );
            print( "        -p/ort <(+)#>    use alternate port (+# to increment port num)\n" );
            print( "        -s/erver <svr>   alternate server to connect to\n" );
            exit( $exitval );                   # exit
        }
        elsif ( $args[$i] =~ /^-d/o )           # debug requested
        {
            $debug = 1;                         # enable debug 
        }
        elsif ( $args[$i] =~ /^-f/o )           # file(s) coming
        {
            # this is here for historical reasons
        }
        elsif ( $args[$i] =~ /^-n/o )           # no close (no shutdown)
        {
            $shutdown = 0;                      # disable shutdown
        }
        elsif ( $args[$i] =~ /^-p/o )           # adjust port
        {
            if ( $args[++$i] =~ /^\+(\d+)$/ )     # +number
            {
                $port += $1;                    # add number to port
            }
            elsif ( $args[$i] =~ /^\d+$/ )      # just a number
            {
                $port = $args[$i];              # use number as port
            }
            else                                # unknown argument
            {
                warn( "$errhdr unknown port argument '$args[$i]'!\n\n" );
                $exitval = 1;                   # set bad exit val
                ParseCmd( '-h' );               # prn help & exit
            }
        }
        elsif ( $args[$i] =~ /^-s/o )           # server
        {
            $server = $args[++$i];              # overwrite default server
        }
        elsif ( -f $args[$i] )                  # if it's a file
        {
            push( @files, $args[$i] );          # add file to list
        }
        else                                    # unknown arg
        {
                                                # prn warning
            warn( "$errhdr unknown argument '$args[$i]'!\n\n" );
            $exitval = 1;                       # set bad exit val
            ParseCmd( '-h' );                   # prn help & exit
        }
    }
}


###########################################################################
#   NAME: PrnDbgHdr
#   DESC: prints debug info
#   ARGS: args sent to calling function
#   RTNS: n/a - prints to STDOUT
###########################################################################
sub PrnDbgHdr
{
    print( "$dbghdr ", (caller( 1 ))[3], '( ', join( ', ', @_ ), " )...\n" );
}


###########################################################################
#   NAME: SendFile
#   DESC: 
#   ARGS: 
#   RTNS: 
###########################################################################
sub SendFile
{
    PrnDbgHdr( @_ ) if ( $debug );              # print debug info if requested

    my $stat = 0;                               # init status var
    my @out = ();                               # init output var

    open( FH, "<$_[0]" ) || die( "$errhdr error reading '$_[0]'!" );
    ($stat, @out) = SocketComm( <FH> );
    close( FH );

    if ( $stat )                                # if non-0 status returned
    {
        warn( "$errhdr error returned from server !\n" );
        die(  "$errspc @out\n" );               # prn svr message & die
    }

    return( @out );                             # return svr message
}



###########################################################################
#   NAME: SocketComm
#   DESC: creates the socket and sends the file through, listens for end tag
#   ARGS: open filehandle to data file
#   RTNS: socket err?, command output
###########################################################################
sub SocketComm
{
    my $xmlstr = join( '', @_ );                # read in str (or entire fh)
    my $exitval = 0;                            # default exit val = okay
    my @cmdout = ();                            # init command output
    my $proto = getprotobyname( 'tcp' );        # get protocol num for tcp
    my $iaddr = inet_aton( $server );           # convert hostname to bin ip
    my $paddr = sockaddr_in( $port, $iaddr );   # resolve socket address

                                                # create socket
    socket( SOCK, PF_INET, SOCK_STREAM, $proto ) or die( "socket: $!" );
                                                # connect to socket
    connect( SOCK, $paddr ) or die( "$errhdr unable to connect to '$server'!\n" );
    autoflush SOCK 1;                           # don't buffer to socket
    print( SOCK "$xmlstr\n" );                  # send command through socket
    shutdown( SOCK, 1 ) if ( $shutdown );       # we're done writing if enabled

    while ( $_ = <SOCK> )                       # while data in socket
    {
        print( "$dbghdr \$_ = $_\n" ) if ( $debug );         
        if ( $_ =~ /status='error'/o )          # error detected
        {
            $exitval = 1;                       # set bad exit val
        }
        push( @cmdout, $_ );                    # save command output
        last if ( $_ =~ /$eof/ );               # stop read if end of data
    }
    close( SOCK );                              # close the socket

    return( $exitval, @cmdout );                # return status & output
}
