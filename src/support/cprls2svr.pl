#!/usr/bin/perl -w
###########################################################################
#   NAME: cprls2svr.pl
#   DESC: copies "released" files to the CQ/XML server install dirs
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
#find $xmldir  -type f              = 0400
#find $xmldir  -type f -name "*.pl" = 0500
#find $datadir -type f              = 0600
#find $xmldir  -type d              = 0700
#$xmldir                            = 0300
# File::Copy, copy() rtn - 0=failure, 1=success

###########################################################################
#   Perl goo
###########################################################################
use File::Copy;                                 # gives up sys/copy()
use Cwd;                                        # current working dir
BEGIN                                           # do this at compile time
{
    ($cmdhdr, $cmddir) = ($0 =~ m|^(.*)[/\\]([^/\\]+)$|o) ? ($2, $1) : ($0, '.');
                                                # fix cmddir if relative
    $cmddir = cwd() . "/$cmddir" if ( $cmddir !~ m#^[/\\]#o );
    $cmddir =~ s|\\|/|og;                       # convert \ -> /
}
use lib "$cmddir";                              # push startup dir to @INC
require( 'cqsvrvars.pm' );                      # server variables
require( 'cqsys.pm' );                          # system-level functions


###########################################################################
#   globals
###########################################################################

### hard-coded ############################################################
my $xmldir = '/opt/cqxmlintf';                  # cq/xml intf install dir
my $datadir = "$xmldir/data";                   # cq/xml intf data dir
my $owner = 'cqxmlusr';                          # default owner = cqxmlusr
my $buext = '.blf';                             # Backup Live File ext
my $crontab = '/usr/bin/crontab';               # crontab executable
my $chklive = 'cqxi_chklive.pl';                # name of chklive process
                                                # prevent "possible typo" warn
my @tmp = ( $CqSvr::livename, $CqSvr::queuename, $CqSvr::swfile, $CqSvr::logdir ); @tmp = ();
### dynamic ###############################################################
my $cmdspc = $cmdhdr; $cmdspc =~ tr/!/ /c;      # basename spacer
my $errhdr = "$cmdhdr: ERROR -";                # error header
my $errspc = $errhdr; $errspc =~ tr/!/ /c;      # err hdr spacer
my $wrnhdr = "$cmdhdr: WARNING -";              # warning header
my $wrnspc = $wrnhdr; $wrnspc =~ tr/!/ /c;      # warn hdr spacer
my $exitval = 0;                                # default exit val = ok
my @files = ();                                 # src files
### user ##################################################################
my $sdir = '';                                  # source directory
my $keepbu = 0;                                 # keep backups


###########################################################################
#   main()
###########################################################################
($sdir, $keepbu) = ParseCmd( @ARGV );           # parse the command line
ChkUsr( $> );                                   # check euid
@files = ReadSrcDir( $sdir );                   # read files in src dir
die( "$errhdr unable to open permissions on '$xmldir'!\n" )
  if ( !chmod( 0770, $xmldir ) );               # die if root chmod failed
if ( BuLiveFiles( $xmldir, @files ) )           # backup the live files failed
{
    exit( RestoreOrig( $xmldir ) );             # put dir back the way it was
}
if ( CpList( $sdir, $xmldir, $owner, @files ) ) # copy src files
{
    exit( RestoreOrig( $xmldir ) );             # put dir back the way it was
}
RmBuFiles( $xmldir ) if ( !$keepbu );           # remove backup files
die( "$errhdr unable to close permissions on '$xmldir'!\n" )
  if ( !chmod( 0300, $xmldir ) );               # die if root chmod failed
PromptRestart( $owner );                        # prompt to restart the live svr
ChkRmStandby();                                 # check if svr in standby


###########################################################################
#   NAME: ParseCmd
#   DESC: parse the command line
#   ARGS: @ARGV
#   RTNS: 
###########################################################################
sub ParseCmd
{
    my @args = @_;                              # save input locally
    my $sdir = '';                              # init src dir var
    my $keep = 0;                               # keep backups?

    for ( my $i=0; defined( $args[$i] ); $i++ ) # go thru args
    {
        if ( $args[$i] =~ /^-h/io )             # this help screen
        {
            select( STDERR ) if ( $exitval );   # prn to ERR if err cond
            print( "USAGE: $cmdhdr [-h|-k] -d <dir>\n" );
            print( "\t-d <dir>  directory to copy from\n" );
            print( "\t-h        this help screen\n" );
            print( "\t-k        keep back-ups\n" );
            exit( $exitval );                   # get out'a here
        }
        elsif ( $args[$i] =~ /^-d/io )          # if dir arg
        {
            if ( -d $args[++$i] )               # if next arg is dir
            {
                $sdir = $args[$i];              # save dir arg
                $sdir =~ s,/*$,,;               # rm trailing '/'
            }
            else                                # next arg ! dir
            {
                $exitval = 1;                   # set bad exit val
                warn( "$errhdr bad source directory argument '$args[$i]'!\n" );
                ParseCmd( '-h' );               # prn help & exit
            }
        }
        elsif ( $args[$i] =~ /^-k/io )          # if keep backups
        {
            $keep = 1;                          # set keep flag
        }
        else                                    # unknown arg
        {
            $exitval = 1;                       # set bad exit val
            warn( "$errhdr unknown argument '$args[$i]'!\n" );
            ParseCmd( '-h' );                   # prn help & exit
        }
    }

    if ( !$sdir )                               # if source dir not set
    {
        $exitval = 1;                           # set bad exit val
        warn( "$errhdr source directory not specified!\n" );
        ParseCmd( '-h' );                       # prn help & exit
    }

    return( $sdir, $keep );                     # rtn src dir & keep bu flag
}


###########################################################################
#   NAME: ChkUsr
#   DESC: check that the user has the proper permissions
#   ARGS: euid
#   RTNS: 0 on success, msg on err
###########################################################################
sub ChkUsr
{
    my $euid = $_[0];                           # effective user id

    print( "$cmdhdr: Checking effective user id...\n" );
    if ( $euid != 0 )                           # if not root
    {
        select( STDERR );                       # prn to STDERR
        print( "$errhdr you must run this script as 'root', not '", (getpwuid( $euid ))[0], "'!\n" );
        print( "\n" );
        print( "\tTo acquire 'root' on the development machines:\n" );
        print( "\t\$ #fix\n" );
        print( "\t\$ #fix\n" );
        print( "\t\$ #fix\n" );
        print( "\n" );
        print( "\tTo acquire 'root' on the production (test) machines:\n" );
        print( "\t\$ #fix\n" );
        print( "\n" );
        exit( 1 );                              # bad exit
    }

    print( "$cmdspc  0 (aka 'root') - that's good.\n" );
    return( 0 );                                # rtn good val
}


###########################################################################
#   NAME: ReadSrcDir
#   DESC: read the files in the src dir
#   ARGS: src dir
#   RTNS: list of files in the src dir
###########################################################################
sub ReadSrcDir
{
    my $srcdir = $_[0];                         # source dir
    my @dir = ();                               # init rtn array

    print( "$cmdhdr: Reading source directory...\n" );
                                                # open `find` pipe | die
    open( READSRC, "find $srcdir -type f -print|" ) ||
      die( "$errhdr unable to read source directory '$srcdir'!\n" );
    chomp( @dir = <READSRC> );                  # read `find` results
    close( READSRC );                           # close the `find` pipe
    map( s/^$srcdir\/?//, @dir );               # rm src dir from filename

    if ( !@dir )                                # if no files found
    {
        warn( "$errhdr no files found in '$srcdir'!\n" );
        $exitval = 1;                           # set bad exit
        ParseCmd( '-h' );                       # give user some info to work w/
    }

    print( "$cmdspc  ", $#dir+1, " files found.\n" );
    return( @dir );                             # return results from `find`
}


###########################################################################
#   NAME: BuLiveFiles
#   DESC: backs-up the files that are about to be copied over
#   ARGS: src dir, files to bu
#   RTNS: 0 on success, >0 on error
###########################################################################
sub BuLiveFiles
{
    my $destdir = shift( @_ );                  # src dir
    my @files = @_;                             # file list

    print( "$cmdhdr: Backing-up current files...\n" );
    foreach $file ( @files )                    # go thru file list
    {
        print( "$cmdspc  $file\n" );
        if ( -f "$destdir/$file" )              # if dest file exists
        {
            return( 1 ) if ( CopyAtribs( "$destdir/$file", "$destdir/$file$buext" ) );
           
                                                # chmod file we're replacing
            if ( !chmod( 0777, "$destdir/$file" ) )
            {
                warn( "$errhdr unable to open permissions on file '$destdir/$file'!\n" );
                return( 1 );                # rtn bad val
            }
        }
        else                                    # not a file?
        {
            warn( "$wrnhdr unable to find file '$destdir/$file'.\n" );
            warn( "$wrnspc If '$file' is new, you can ignore this warning.\n" );
        }
    }

    print( "$cmdspc  ", $#files+1, " files backed-up (or new).\n" );
    return( 0 );                                # 
}


###########################################################################
#   NAME: CopyAtribs
#   DESC: copies a file & its attributes to another file
#   ARGS: orig file, new file
#   RTNS: 0 on success, 1 on error
###########################################################################
sub CopyAtribs
{
    my $src = $_[0];                            # source file
    my $new = $_[1];                            # destination file
    my @stat = ();                              # src file info

    if ( -f "$src" )                            # if src file exists
    {
        @stat = (stat( "$src" ))[2,4,5];        # save mode, uid, gid
        if ( copy( "$src", "$new" ) )           # if copy was ok
        {
                                                # cp perms from old to new file
            if ( !chmod( $stat[0] & 07777, "$new" ) )
            {
                warn( "$errhdr unable to copy permissions to new file '$new'!\n" );
                return( 1 );                    # rtn bad val
            }
                                                # cp owner/grp from old to new
            elsif ( !chown( @stat[1,2], "$new" ) )
            {
                warn( "$errhdr unable to copy owner/group to new file '$new'!\n" );
                return( 1 );                    # rtn bad val
            }
        }
        else                                    # copy failed
        {
            warn( "$errhdr unable to copy file '$src' to '$new'!\n" );
            warn( "$errspc $!\n" );
            return( 1 );                        # rtn bad val
        }
    }
    else                                        # not a file?
    {
        warn( "$errhdr unable to fine file '$src'!\n" );
        return( 1 );                            # rtn bad val
    }

    return( 0 );                                # rtn ok val
}


###########################################################################
#   NAME: RestoreOrig
#   DESC: restores the directory back the way it was
#   ARGS: dir to restore
#   RTNS: 0 on success, >0 on error
###########################################################################
sub RestoreOrig
{
    my $dir = $_[0];                            # dir to search thru
    my $orig = '';                              # original filename
    my $err = 0;                                # init err ctr
    my $newctr = 0;                             # new file counter

                                                # prompt user
    print( "\a$errhdr Due to the previous error, the CQ/XML Interface\n" );
    print( "$errspc directory will be restored to its previous state.\n" );
    print( "$errspc Press <CR> to continue or enter 'q' to quit: " );
    chomp( $orig = <STDIN> );                   # var reuse = bad idea, oh well
    die( "$errhdr directory restoration aborted by user!\n" )
      if ( $orig =~ /^q/iog );

    foreach $file ( ListBuFiles( $dir ) )       # go thru the backup files
    {
        $file =~ /^(.*)$buext/;                 # get orig filename
        $orig = $1;                             # original filename
        chmod( 0666, $orig );                   # try to make the orig r/w
        if ( -s $file )                         # if backup file has contents
        {
            if ( !rename( $file, $orig ) )      # if rename failed
            {
                $err++;                         # inc err ctr
                warn( "$errhdr unable to rename '$file' -> '$orig'!\n" );
                warn( "$errspc $!\n" );
            }
        }
        else                                    # if bu file empty
        {
            $newctr++;                          # inc 'new' couner
            if ( unlink( $file, $orig ) != 2 )  # if rm failed
            {
                $err++;                         # inc err ctr
                warn( "$errhdr unable to remove new file '$orig($buext)'!\n" );
            }
        }
    }

    warn( "$wrnhdr Directory restoration complete, $err errors encountered!\n" );
    warn( "$wrnspc Directories created for the $newctr new files may still remain.\n" ) if ( $newctr );
    return( $err );                             # return err ctr
}


###########################################################################
#   NAME: ListBuFiles
#   DESC: list the backup files
#   ARGS: dir to look in
#   RTNS: array of files on success, 0 on error
###########################################################################
sub ListBuFiles
{
    my $dir = $_[0];                            # dir to search thru
    my @rtn = ();                               # init

    open( READDIR, "find $dir -type f -name '*$buext' -print|" ) ||
      die( "$errhdr unable to clean directory '$dir'!" );
    chomp( @rtn = <READDIR> );                  # read `find` results
    close( READDIR );                           # close the `find` pipe

    return( @rtn );                             # return files found
}


###########################################################################
#   NAME: CpList
#   DESC: copies the list of new files to the specified dir
#   ARGS: src dir, dest dir, owner, files
#   RTNS: 0 on success, 1 on error
###########################################################################
sub CpList
{
    my $src = shift( @_ );                      # src dir
    my $dest = shift( @_ );                     # dest dir
    my $owner = shift( @_ );                    # owner
    my @files = @_;                             # file list
    my $subdir = '';                            # new sub dir that file lives in

    print( "$cmdhdr: Copying source files...\n" );
    foreach $file ( @files )                    # go thru filelist
    {
        if ( $file =~ m#^(.*)/[^/]+$# )         # if subdirs
        {
            $subdir = $1;                       # save sub dir
            if ( MkSubDirs( $dest, $subdir ) )  # if prob mk'ing sub dir
            {
                warn( "$errhdr unable to create sub-directory '$subdir'!\n" );
                return( 1 );                    # return err
            }
                                                # if chown failed
            elsif ( !chown( (getpwnam( $owner ))[2,3], "$dest/$subdir" ) )
            {
                warn( "$errhdr unable to change owner on directory '$dest/$subdir'!\n" );
                return( 1 );                    # return err
            }
        }
                                                # if copy failed
        if ( !copy( "$src/$file", "$dest/$file" ) )
        {
            warn( "$errhdr unable to copy file '$file'!\n" );
            return( 1 );                        # return err
        }
        elsif ( -f "$dest/$file$buext" )        # replacing file
        {
                                                # if cp perms from bu file ok
            if ( chmod( (stat( "$dest/$file$buext" ))[2] & 07777, "$dest/$file" ) )
            {
                                                # if chown failed
                if ( !chown( (getpwnam( $owner ))[2,3], "$dest/$file" ) )
                {
                    warn( "$errhdr unable to change owner on file '$file'!\n" );
                    return( 1 );                # return err
                }
            }
            else                                # chmod failed
            {
                warn( "$errhdr unable to change permissions on file '$file'!\n" );
                return( 1 );                    # return err
            }
        }
        else                                    # new file
        {
                                                # touch the backup file
            open( TOUCH, ">>$dest/$file$buext" ) && close( TOUCH );
                                                # chmod w/ prompting
            return( 1 ) if ( PromptChmod( $dest, $file ) );
        }
    }

    print( "$cmdspc  ", $#files+1, " files copied.\n" );
    return( 0 );                                # return good value
}


###########################################################################
#   NAME: MkSubDirs
#   DESC: makes a sub dir tree
#   ARGS: dir to look in, sub dir to make
#   RTNS: 0 on success, 1 on error
###########################################################################
sub MkSubDirs
{
    my $last = $_[0];                           # top of dir tree
    my $tree = $_[1];                           # the tree to make

    print( "\n$cmdhdr: making subdirectory '$tree'..." );
    foreach $dir ( split( '/', $tree ) )        # go thru sub dirs
    {
        if ( -d "$last" )                       # last dir okay
        {
            mkdir( "$last/$dir", 0700 );        # make new dir
            $last .= "/$dir";                   # add current dir to last
        }
        else                                    # prob w/ last dir
        {
            print( " error!\n" );               # throw error message
            return( 1 );                        # return bad val
        }
    }
    print( " done.\n" );
    return( 0 );                                # return ok val
}


###########################################################################
#   NAME: PromptChmod
#   DESC: does a chmod with some prompting
#   ARGS: directory, file
#   RTNS: 0 on success, 1 on error
###########################################################################
sub PromptChmod
{
    my $dir = $_[0];                            # dest dir
    my $file = $_[1];                           # dest file
    my $pmod = '';                              # prompted mod

    print( "\n\a$cmdhdr: Found new file '$file'.\n" );
    print( "$cmdspc  Please specify permissions (ex: 400) or [q]uit: " );
    chomp( $pmod = <STDIN> );                   # save user answer

    if ( $pmod =~ /^0?(\d{3})$/ )               # if valid perm
    {
                                                # if chmod failed
        if ( !chmod( oct( "0$pmod" ), "$dir/$file" ) )
        {
            warn( "$errhdr unable to change permissions on '$file' to '0$pmod'!\n" );
            warn( "$errspc Let's try this again...\n" );
                                                # try again
            return( PromptChmod( $dir, $file ) );
        }
    }
    elsif ( $pmod =~ /^q/iog )                  # quit
    {
        warn( "$errhdr operation aborted by user!\n" );
        return( 1 );                            # return bad val
    }
    else                                        # invalid perm
    {
        warn( "$errhdr invalid permissions '$pmod' specified!\n" );
        return( PromptChmod( $dir, $file ) );   # try again
    }

    return( 0 );                                # return okay val
}


###########################################################################
#   NAME: RmBuFiles
#   DESC: removes all the backup files (*$buext)
#   ARGS: dir to clean out
#   RTNS: 0 on success, # of remaining files on error
###########################################################################
sub RmBuFiles
{
    my $dir = $_[0];                            # dir to search thru
    my @filelist = ();                          # init file list
    my $rmctr = 0;                              # rm counter

    print( "$cmdhdr: removing backup files...\n" );
    @filelist = ListBuFiles( $dir );            # gen list of backup files

    chmod( 0666, @filelist );                   # open up the file perms
    $rmctr = unlink( @filelist );               # rm bu files & save count

    if ( $rmctr <= $#filelist )                 # ! all rm'd
    {
        warn( "$wrnhdr unable to remove all of the backup files.\n" );
        return( $#filelist + 1 - $rmctr );      # rtn # of remaining files
    }
    print( "$cmdspc  $rmctr files removed.\n" );
    return( 0 );                                # return ok val
}


###########################################################################
#   NAME: PromptRestart
#   DESC: prompt to restart the live server
#   ARGS: crontab owner
#   RTNS: 0 on success, 1 on error
###########################################################################
sub PromptRestart
{
    my $user = $_[0];                           # save crontab owner locally
    my $procerrs = '';                          # find proc errs (anon-array)
    my %procs = ();                             # find procs (pid=>args)
    my $prnfmt = "  %-2s  %-5s  %s\n";          # menu format
    my $ctr = 0;                                # init counter
    my @pidlist = ();                           # list of CQ/XML pids
    my $answer = '';                            # user's answer

    ($procerrs, %procs) = CqSys::FindSvrProcs( "$CqSvr::livename", 0 );

    if ( $procerrs && !%procs )                 # if errs & no procs
    {
        warn( "$wrnhdr unable to find XML Live Server process!\n" );
        warn( "$wrnspc ", @{$procerrs}, "\n" );
        return( 1 );                            # return err
    }

    print( "\n" );                              # print the header
    print( "$cmdhdr: To stop the XML Live Server process, select the\n" );
    print( "$cmdspc  appropriate process from the following list.\n" );
    print( "\n" );
    printf( "$cmdspc$prnfmt", '#', 'PID', 'OPTS' );
    print( "$cmdspc  ", '-'x20, "\n" );
    foreach $proc ( sort( keys( %procs ) ) )    # go thru detected procs
    {
        printf( "$cmdspc$prnfmt", $ctr++, $proc, $procs{$proc} );
        push( @pidlist, $proc );                # add pid to list
    }
    printf( "$cmdspc$prnfmt", 'q', 'Quit', '' );
    print( "$cmdspc  ", '-'x20, "\n" );
    print( "$cmdspc> " );
    chomp( $answer = <STDIN> );                 # read user's answer

    if ( $answer =~ /^q/io )                    # quit
    {
        return( 0 );                            # return ok
    }
                                                # valid response
    elsif ( $answer =~ /^\d+$/ && $answer <= $#pidlist )
    {
        return( KillStatus( $pidlist[$answer], $user ) );
    }
    else                                        # invalid response
    {
        warn( "$errhdr invalid selection '$answer'!\n" );
        return( PromptRestart( $user ) );       # try again
    }
}


###########################################################################
#   NAME: KillStatus
#   DESC: kills the process and says when it'll restart
#   ARGS: pid, 
#   RTNS: 0 on success, 1 on error
###########################################################################
sub KillStatus
{
    my $pid = $_[0];                            # pid to kill
    my $usr = $_[1];                            # user's crontab to inspect
    my $hr = (gmtime( time() ) )[2];            # current hour
    my $min = (gmtime( time() ))[1];            # current minute
    my @ctout = ();                             # crontab output

    if ( !kill( 'KILL', $pid ) )                # if kill failed
    {
        warn( "$errhdr unable to kill process '$pid'!\n" );
        return( 1 );
    }
    printf( "$cmdhdr: %-40s %02d:%02d\n", 'Current time is:', $hr, $min );
    chomp( @ctout = `$crontab -u $usr -l` );    # crontab of specified user
                                                # 
    printf( "$cmdspc  %-40s %02d:%02d\n", 'XML Live Server will restart at:', 
      NextCronTime( $hr, $min, (grep( /$cmddir\/$chklive/, @ctout ))[0] ) );

    printf( "$cmdspc  %-40s %02d:%02d\n",
      'XML Queue Manager will use new code at:',
      NextCronTime( $hr, $min, (grep( /$cmddir\/$CqSvr::queuename/, @ctout ))[0] ) );
    return( 0 );
}


###########################################################################
#   NAME: NextCronTime
#   DESC: returns next time cron will run
#   ARGS: hr, min, cron line
#   RTNS: hr, min of next cron job
###########################################################################
sub NextCronTime
{
    my $hr = $_[0];                             # cur hr
    my $min = $_[1];                            # cur min
    my $cronline = $_[2];                       # cron line
    my @crontimes = ();                         # cron times
    my $next = 0;                               # init next min var

    $cronline =~ s/^\s*([\d,]+)\s.*$/$1/;       # save cron minutes
                                                # sort the minutes
    @crontimes = sort( {$a <=> $b} split( /,/, $cronline ) );
    $next = (sort( {$min >= $a} @crontimes))[0]; # get next one > cur min
    if ( $next < $min )                         # if that didn't work, no match
    {
        return( $hr+1, $crontimes[0] );         # return next hr & 1st min
    }
    else                                        # still in this hr
    {
        return( $hr, $next );                   # return cur hr & next min
    }
}


###########################################################################
#   NAME: ChkRmStandby
#   DESC: checks if server is in standby, if so ask if that's right
#   ARGS: n/a
#   RTNS: n/a
###########################################################################
sub ChkRmStandby
{
    my @standbytmps = <$xmldir/$CqSvr::logdir/$CqSvr::swfile*>;
    my $answer = '';

    return if ( !@standbytmps );                # 
    print( "\n" );
    print( "$cmdhdr: The XML Server is currently in the standby state.\n" );
    print( "$cmdspc  Would you like CQ/XML transactions to resume?\n" );
    print( "$cmdspc  [Y/n]: " );
    chomp( $answer = <STDIN> );

    if ( $answer =~ /^n/io )                    # no!
    {
        warn( "$wrnhdr the CQ/XML server remains in the standby state!\n" );
        warn( "$wrnspc If you have reached this message in error, refer\n" );
        warn( "$wrnspc to the CQ/XML Admin documentation to take the\n" );
        warn( "$wrnspc server out of standby mode.\n" );
    }
    else
    {
                                                # if unlink ok
        if ( unlink( @standbytmps ) == $#standbytmps+1 )
        {
            print( "$cmdhdr: Standby mode discontinued successfully.\n" );
        }
        else
        {
            warn( "$errhdr unable to remove all of the standby tmp files!\n" );
            warn( "$errspc Refer to the CQ/XML Admin documentation to fix\n" );
            warn( "$errspc this problem.\n" );
        }
    }
}
