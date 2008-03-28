###########################################################################
#   NAME: cqsvrfuncs.pm
#   DESC: 
#   PKG:  CqSvr
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
package CqSvr;
use Crypt::RC4;                                 # get some RC4 encryption going
require( 'cqsvrvars.pm' );                      # server variables
                                                # set pkg flags based on main
$debug  = defined( $main::debug )  ? $main::debug  : 0;
$errhdr = defined( $main::errhdr ) ? $main::errhdr : 'ERROR:';

###########################################################################
#   NAME: PrnDbgHdr
#   DESC: prints debug info
#   ARGS: args sent to calling function
#   RTNS: n/a - prints to STDOUT
###########################################################################
sub PrnDbgHdr
{
    my $prndbghdr = defined( $dbghdr ) ? $dbghdr : 'DEBUG: ';
    print( $prndbghdr, (caller( 1 ))[3] );
    if ( $debug == 1 )                          # std debug output
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


###########################################################################
#   NAME: MkDirTree
#   DESC: creates a directory tree
#   ARGS: tree to make
#   RTNS: 0 on success, 0 on exists, err msg on error
###########################################################################
sub MkDirTree
{
    PrnDbgHdr( @_ ) if ( $debug );              # print debug info if requested

    my $destdir = $_[0];                        # save dir name
    my $newdir = $destdir =~ m#^/# ? '' : '.';  # if full dir, nothing, else '.'
    my $rtn = 0;                                # default return = ok

    if ( ! -d "$destdir" )                      # if dest dir doesn't exist
    {
                                                # go thru dir sub dirs
        foreach $dir ( split( '/', "$destdir" ) )
        {
                                                # if make subdir failed, die
            return( "$errhdr unable to make directory '$newdir/$dir'!" )
              if ( ! -d "$newdir/$dir" && !mkdir( "$newdir/$dir", 0700 ) );
            $newdir .= "/$dir";                 # append created dir
        }
    }

    return( $rtn );                             # return success/failure
}


###########################################################################
#   NAME: OpenLog
#   DESC: opens the log file and positions file ptr over root elem close
#   ARGS: filename, quiet?
#   RTNS: filehandle ref
###########################################################################
sub OpenLog
{
    PrnDbgHdr( @_ ) if ( $debug );              # print debug info if requested

    my $logfile = $_[0];                        # log file name
    my $quiet = defined( $_[1] ) ? $_[1] : 0;   # quiet?
    #my $seekoffset = $CqSvr::osiswin ? 5 : 4;   # determine seek offset by os
    my $seekoffset = 4;
                                                # len of root elem + </ + > + \n
    my $seeklen = length( $CqSvr::rootelem ) + $seekoffset; 
                                                # size of log file
    my $filesize = -f $logfile ? -s $logfile : 0;

    print( "$main::cmdhdr (PID:$$) ", ShortDateNTime(), "\n" ) if ( !$quiet );

    if ( $filesize > ($seeklen*2) )             # if log file > root elem & end
    {
                                                # open for read/write or die
        open( LOG, "+<$logfile" ) || die( "$errhdr unable to read/write log file '$logfile'!\n" );
        binmode( LOG );                         # write in binary mode
        seek( LOG, $seeklen*-1, 2 );            # move file ptr over end elem
        print( LOG "\n" );                      # an extra space for readability
    }
    elsif ( open( LOG, ">$logfile" ) )          # if file too small, overwrite
    {
        binmode( LOG );                         # write in binary mode
                                                # prn sys msg if exists
        print( LOG "$CqSvr::sysmsg\n" ) if ( $CqSvr::sysmsg );
        print( LOG "<$CqSvr::rootelem>\n" );    # prn root element
    }
    else                                        # if file too sml & open failed
    {
        die( "$errhdr unable to write to log file '$logfile'!\n" );
    }

    autoflush LOG 1;                            # don't buffer to log file
    return( \*LOG );                            # return fh ref
}


###########################################################################
#   NAME: ReadIpModPerms
#   DESC: reads the ip modification permissions file
#   ARGS: n/a
#   RTNS: hash of ip=>record-type=>field=>[values]
###########################################################################
sub ReadIpModPerms
{
    PrnDbgHdr( @_ ) if ( $debug );              # print debug info if requested

                                                # file modification date
    my $filemod = (stat( $CqSvr::recmodxml ))[9];
    my $xmldoc  = undef;                        # xml doc obj
    my %xmlread = ();                           # parsed xml
    my $cleanip = '';                           # ip cleaned of xml goo
    my %perms   = ();                           # permissions hash structure

    return( %CqSvr::modperms )                  # rtn old data if file ! chg'd
      if ( defined( $CqSvr::filestat{$CqSvr::recmodxml} ) && $filemod == $CqSvr::filestat{$CqSvr::recmodxml} );
    ChgDataPerms( $CqSvr::recmodxml );          # fix the permissions
                                                # open data file | rtn 0
    open( PERMS, "<$CqSvr::recmodxml" ) || return( %perms );
    $xmldoc = XML::Mini::Document->new();       # create new xml doc obj
                                                # parse data file
    eval{ $xmldoc->parse( *PERMS ); %xmlread = %{${$xmldoc->toHash()}{$CqSvr::recmodroot}} };
    close( PERMS );                             # close data file
                                                # save new mod date to pkg var
    $CqSvr::filestat{$CqSvr::recmodxml} = $filemod;

    foreach $ip ( keys( %xmlread ) )            # go thru ip's
    {
                                                # clean off leading "ip"
        $cleanip = $ip =~ /^ip([\.\d]+)$/ ? $1 : $ip;
                                                # if unknown data struct, ignore
        next if ( ref( $xmlread{$ip} ) ne 'HASH' );
                                                # go thru record types
        foreach $rectype ( keys( %{$xmlread{$ip}} ) )
        {
                                                # go thru record fields
            foreach $field ( keys( %{${$xmlread{$ip}}{$rectype}} ) )
            {
                                                # if 1 value
                if ( !ref( ${${$xmlread{$ip}}{$rectype}}{$field} ) )
                {
                                                # force into anon array
                    ${${$perms{$cleanip}}{$rectype}}{$field} = [ ${${$xmlread{$ip}}{$rectype}}{$field} ];
                }
                                                # if >1 value
                elsif ( ref( ${${$xmlread{$ip}}{$rectype}}{$field} ) eq 'ARRAY' )
                {
                                                # save them all
                    ${${$perms{$cleanip}}{$rectype}}{$field} = ${${$xmlread{$ip}}{$rectype}}{$field};
                }
            }
        }
    }

    return( %perms );                           # return permissions hash
}


###########################################################################
#   NAME: ReadEncKeys
#   DESC: reads the password encryption keys
#   ARGS: n/a
#   RTNS: hash of ip/user=>key
###########################################################################
sub ReadEncKeys
{
    PrnDbgHdr( @_ ) if ( $debug );              # print debug info if requested

                                                # file modification date
    my $filemod = (stat( $CqSvr::encryptxml ))[9];
    my $xmldoc  = undef;                        # xml doc obj
    my %xmlread = ();                           # parsed xml
    my %keys    = ();                           # encryption keys hash
    my $cleanid = '';                           # id cleaned of xml goo

    return( %CqSvr::enckeys )                   # rtn old data if file ! chg'd
      if ( defined( $CqSvr::filestat{$CqSvr::encryptxml} ) && $filemod == $CqSvr::filestat{$CqSvr::encryptxml} );
    ChgDataPerms( $CqSvr::encryptxml );         # fix the permissions
                                                # open data file | rtn 0
    open( PERMS, "<$CqSvr::encryptxml" ) || return( %perms );
    $xmldoc = XML::Mini::Document->new();       # create new xml doc obj
                                                # parse data file
    eval{ $xmldoc->parse( *PERMS ); %xmlread = %{${$xmldoc->toHash()}{$CqSvr::enckeyroot}} };
    close( PERMS );                             # close data file
                                                # save new mod date to pkg var
    $CqSvr::filestat{$CqSvr::encryptxml} = $filemod;

    foreach $enctype ( keys( %xmlread ) )       # enc by ip or user
    {
                                                # if unknown data struct, ignore
        next if ( ref( $xmlread{$enctype} ) ne 'HASH' );
                                                # go thru id's
        foreach $id ( keys( %{$xmlread{$enctype}} ) )
        {
                                                # clean off leading "ip"
            $cleanid = $id =~ /^ip([\.\d]+)$/ ? $1 : $id;
                                                # if just the key
            if ( !ref( ${$xmlread{$enctype}}{$id} ) )
            {
                                                # save the pcdata
                $keys{$cleanid} = ${$xmlread{$enctype}}{$id};
            }
                                                # if atribs & junk
            elsif ( defined( ${${$xmlread{$enctype}}{$id}}{'-content'} ) )
            {
                                                # just save the pcdata
                $keys{$cleanid} = ${${$xmlread{$enctype}}{$id}}{'-content'};
            }
        }
    }

    return( %keys );                            # return enc keys hash
}


###########################################################################
#   NAME: ReadSysMsg
#   DESC: reads the system status message
#   ARGS: n/a
#   RTNS: system status string
###########################################################################
sub ReadSysMsg
{
    PrnDbgHdr( @_ ) if ( $debug );              # print debug info if requested

                                                # file modification date
    my $filemod  = (stat( $CqSvr::sysmsgtxt ))[9];
    my @contents = ();                          # file contents
    my $filestr  = '';                          # file contents as string
    my $warning  = $^W;                         # save warnings en/disabled

    return( $CqSvr::sysmsg )                    # rtn old data if file ! chg'd
      if ( defined( $CqSvr::filestat{$CqSvr::sysmsgtxt} ) && $filemod == $CqSvr::filestat{$CqSvr::sysmsgtxt} );
    ChgDataPerms( $CqSvr::sysmsgtxt );          # fix the permissions
                                                # open data file | rtn ''
    open( SYSMSG, "<$CqSvr::sysmsgtxt" ) || return( $filestr );
    $^W = 0;                                    # hid file empty & RE warnings
    chomp( @contents = <SYSMSG> );              # read in file contents
    close( SYSMSG );                            # close data file
    $filestr = join( "\n", @contents );         # join contents into 1 string

                                                # format if something there
    $filestr = "<!-- $CqSvr::sysmsghdr: $filestr -->" if ( $filestr =~ /\S/ );
    $^W = $warning;                             # put warnings back

                                                # save new mod date to pkg var
    $CqSvr::filestat{$CqSvr::sysmsgtxt} = $filemod;

    return( $filestr );                         # return string
}


###########################################################################
#   NAME: ChkSysWait
#   DESC: check if a sys wait tmp file is sitting around
#   ARGS: n/a
#   RTNS: 0 if no wait, else cqtan of issuing cmd & pcdata sent w/ cmd
###########################################################################
sub ChkSysWait
{
    PrnDbgHdr( @_ ) if ( $debug );              # print debug info if requested

    my @dirjunk = ();                           # init tmp var
    my $sysmsg  = 'message unavailable';        # default system message

    if ( opendir( LOGDIR, $CqSvr::fulllogdir ) ) # if logdir open ok
    {
        @dirjunk = readdir( LOGDIR );           # read contents of logdir
        closedir( LOGDIR );                     # close logdir FH
                                                # if syswait file found
        if ( @dirjunk = grep( /$CqSvr::swfile/, @dirjunk ) )
        {
                                                # open for read
            if ( open( SYSWAIT, "<$CqSvr::fulllogdir/$dirjunk[0]" ) )
            {
                                                # drink it in
                $sysmsg = join( "\n", <SYSWAIT> );
                close( SYSWAIT );
            }
                                                # should only be 1, save cqtan
            $dirjunk[0] =~ s/^.*$CqSvr::swfile//;
            return( $dirjunk[0], $sysmsg );     # rtn cqtan & system msg
        }
    }
    else                                        # can't read log dir!
    {
        return( 1, $sysmsg );                   # rtn fake cqtan
    }
    return( );                                  # default: no sys wait
}


###########################################################################
#   NAME: ChgDataPerms
#   DESC: tightens the permissions on the file and it's parent dir
#   ARGS: file to fix
#   RTNS: number of files successfully chk'd
#   NOTE: this function should rtn '2' - 1 for the file & 1 for the parent
###########################################################################
sub ChgDataPerms
{
    PrnDbgHdr( @_ ) if ( $debug );              # print debug info if requested

    my $file = $_[0];                           # file to chg
    my $rtn = 0;                                # chmod ctr

    if ( -d $file )                             # if arg is a dir
    {
        $rtn = chmod( 0700, $file );            # was chmod successful?
    }
    else                                        # arg is a file (or close)
    {
        $rtn = chmod( 0600, $file );            # was chmod successful?
        $file =~ s#/[^/]+$##;                   # let's get the parent dir too
        $rtn += ChgDataPerms( $file );          # chg perms on parent dir
    }

    return( $rtn );                             # rtn num of chgs
}


###########################################################################
#   NAME: Decrypt
#   DESC: uses the saved key to decrypt the password
#   ARGS: client ip, login, password
#   RTNS: decrypted password on success, null on failure
###########################################################################
sub Decrypt
{
    PrnDbgHdr( @_ ) if ( $debug );              # print debug info if requested

    my $ip      = $_[0];                        # client ip
    my $login   = $_[1];                        # user login
    my $pswd    = $_[2];                        # user password
    my $rtn     = '';                           # init rtn pswd

                                                # if ip is mapped
    if ( defined( $CqSvr::enckeys{$ip} ) )
    {
                                                # use ip key to decrypt pswd
        $rtn = RC4( $CqSvr::enckeys{$ip}, $pswd );
    }
                                                # if ip !mapped, login mapped
    elsif ( defined( $CqSvr::enckeys{$login} ) )
    {
                                                # use login key to decrypt pswd
        $rtn = RC4( $CqSvr::enckeys{$login}, $pswd );
    }

    return( $rtn );                             # return decrypted str | null
}


###########################################################################
#   NAME: Log2Xml
#   DESC: save events to the log file in xml
#   ARGS: file handle, element, anon-hash of attributes, pcdata, closing opts
#   RTNS: n/a
###########################################################################
sub Log2Xml
{
    PrnDbgHdr( @_ ) if ( $debug );              # print debug info if requested

    my $prevfh = select( $_[0] );               # prn to log fh & save cur fh
                                                # if elem starts with num, fix
    my $elem = $_[1] =~ /^\d/ ? "$CqSvr::qelempre$_[1]" : $_[1];
                                                # deref attributes
    my %atrbs = defined( $_[2] ) ? %{$_[2]} : ();
    my $pcdata = defined( $_[3] ) ? $_[3] : ''; # save pcdata
    my $closeopt = defined( $_[4] ) ? $_[4] : 0; # closing options

    print( "<$elem" );                          # start elem
    foreach $atrb ( sort( keys( %atrbs ) ) )    # go thru attributes
    {
        print( " $atrb='$atrbs{$atrb}'" );      # prn attribute & value
    }

    if ( $closeopt )                            # if closing disabled
    {
        print( ">\n" );                         # prn end of start
    }
    elsif ( $pcdata )                           # if closing & pcdata
    {
        print( ">$pcdata</$elem>\n" );          # prn pcdata & close
    }
    else                                        # if closing & no pcdata
    {
        print( "/>\n" );                        # prn close
    }

    select( $prevfh );                          # set default filehandle back
}


###########################################################################
#   NAME: GenSvrLog
#   DESC: uses CqSvr::Log2Xml() to write a server entry to the log file
#   ARGS: log dir, live/queue filename, anon-hash of attributes, (pcdata)
#   RTNS: n/a
###########################################################################
sub GenSvrLog
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $logdir = $_[0];                         # log dir
    my $logsrc = $_[1];                         # live or queued filename
    my %atrbs  = %{$_[2]};                      # attributes
    my $pcdata = defined( $_[3] ) ? $_[3] : ''; # pcdata
    my $epoch     = time();                     # epoch
    my @date      = (gmtime( $epoch ))[5,7];    # year & day of yr
                                                # join yr, day of yr & 's'
    my $datestr   = sprintf( "%02d%03ds", $date[0]-100, $date[1] );
    my $svrlogctr = '000000';                   # counter
    my $svrlogfh  = undef;                      # server log filehandle

    $svrlogctr = sprintf( "%06d", ++$svrlogctr ) # some file exists, inc ctr
      while ( -f "$logdir/$CqSvr::ipqfile$datestr$svrlogctr"
              || -f "$logdir/$logsrc$datestr$svrlogctr"
              || -f "$logdir/$CqSvr::arcdir/$logsrc$datestr$svrlogctr" );
                                                # open log file
    if ( open( SVRLOG, ">$logdir/$CqSvr::ipqfile$datestr$svrlogctr" ) )
    {
        autoflush SVRLOG 1;                     # don't buffer to log file
                                                # dump std svr log stuff
        CqSvr::Log2Xml( \*SVRLOG, "svr$epoch", {date => CqSvr::ShortDateNTime(), pid => $$, %atrbs}, "$pcdata" );
        close( SVRLOG );                        # close log file
                                                # rename so q_mgr picks it up
        rename( "$logdir/$CqSvr::ipqfile$datestr$svrlogctr", "$logdir/$logsrc$datestr$svrlogctr" );
    }
    else                                        # can't write to log
    {
        die( "$errhdr unable to write to '$logdir/$CqSvr::ipqfile$datestr$svrlogctr'!" );
    }
}


###########################################################################
#   NAME: ShortDateNTime
#   DESC: returns date & time in yyyy/mm/dd 0h:0m:0s TZ format
#   ARGS: n/a
#   RTNS: string of date, time, tz
###########################################################################
sub ShortDateNTime
{
    PrnDbgHdr( @_ ) if ( $debug );              # print debug info if requested

    my @date = gmtime( time() );                # save local time to array
    my $rtnstr = sprintf( "%4d/%02d/%02d %02d:%02d:%02d GMT",
                          $date[5] + 1900, $date[4] + 1, $date[3],
                          $date[2], $date[1], $date[0] );

    return( $rtnstr );                          # return date, time, tz
}

1;
