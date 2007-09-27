#!/usr/bin/perl -w
###########################################################################
#   NAME: cpsysmsg.pl
#   DESC: copies the system message to the xml interface & the rss feed
#   RTNS: non-0 on error
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
require( 'smtpmail.pm' );                       # SMTP mail package

###########################################################################
#   globals that may get inherited
###########################################################################
local $cmdhdr = $0 =~ /([^\/\\]+)$/o ? $1 : $0; # basename
local $errhdr = "\a$cmdhdr: ERROR -";           # error header
local $errspc = $errhdr; $errspc =~ tr/!/ /c;   # error header spacing

###########################################################################
#   static variables
###########################################################################
                                                # sys msg output location
my $srcsmfile = '//cqmsgsvr/cqweb$/sys_message.js';
                                                # system message src location
my $xmlsmfile = '//indshare/sysmsg.txt';
my $xmllmfile = '//indshare/sysmsglong.txt';
                                                # CQ RSS location
my $rsssmfile = '//cqmsgsvr/cqweb$/rss/cqrss.xml';
                                                # cq downtime page
my $downtime  = 'http://engrdocs.site/clearquest/downtimes.html';
my $mailadrs  = 'cqsupport@mentor.com';            # to/from address

###########################################################################
#   dynamic variables
###########################################################################
my $gmtdate = gmtime( time() );                 # GMT
   $gmtdate =~ s/(\d+)\s*$/GMT $1/;             # insert "GMT" into date str
my $newsmsgtxt = '';                            # contents of src short msg
my $newlmsgtxt = '';                            # contents of src long msg
my $oldmsgtxt = '';                             # contents of xml sys msg file
my $rssmsgtxt = '';                             # contents of rss sys msg file
my $force     = 0;                              # force update
my $nomail    = 0;                              # no email
my $statonly  = 0;                              # status only
my $exitval   = 0;                              # default exit value


###########################################################################
#   main()
###########################################################################
ParseCmd( @ARGV );                              # parse the cmd line
                                                # if force | src newer
if ( $force || (stat( $srcsmfile ) )[9] > (stat( $xmlsmfile ) )[9] )
{
    $newlmsgtxt = FileDump( $srcsmfile );       # read src sys msg file
                                                # throw err if nothing in there
    SendMailMsg( 'Error', "$errhdr unable to read system message file at:\n$errspc '$srcsmfile'", 1, $nomail ) if ( !$newlmsgtxt );
                                                # rm HTML formatting
    ($newsmsgtxt, $newlmsgtxt) = CleanSysMsg( $newlmsgtxt );
                                                # read xml sys msg file if exist
    $oldmsgtxt = FileDump( $xmllmfile ) if ( -f $xmllmfile );
}

if ( $force || $newlmsgtxt ne $oldmsgtxt )      # if force | new msg != old msg
{
    die( "$errhdr saved system message differs from current system message!\n" ) if ( $statonly );
    SendMailMsg( 'Updated', "$cmdhdr: received updated system message from '$srcsmfile'", 0, $nomail );
    WriteFile( $xmlsmfile, $newsmsgtxt );       # write new xml file
    WriteFile( $xmllmfile, $newlmsgtxt );       # write new long file
    if ( $newsmsgtxt )                          # if text in sys msg
    {
        $rssmsgtxt = -f $rsssmfile              # if rss file exists
                       ? FileDump( $rsssmfile ) #  read rss file
                       : GenRssStarter();       # else, fake new rss file
                                                # add new msg to rss feed
        $rssmsgtxt = Add2Rss( $rssmsgtxt, $newsmsgtxt, $newlmsgtxt );
        WriteFile( $rsssmfile, $rssmsgtxt );    # write out rss file
    }
}


###########################################################################
#   NAME: ParseCmd
#   DESC: parses the command line
#   ARGS: @ARGV
#   RTNS: n/a
###########################################################################
sub ParseCmd
{
    my @argv = @_;                              # save args to local val

    for ( my $i=0; defined( $argv[$i] ); $i++ ) # go thru args
    {
        if ( $argv[$i] =~ /^-f/ )               # force
        {
            $force = 1;                         # set flag
        }
        elsif ( $argv[$i] =~ /^-n/ )            # no mail
        {
            $nomail = 1;
        }
        elsif ( $argv[$i] =~ /^-s/ )            # status
        {
            $statonly = 1;                      # set flag
            $nomail   = 1;                      # no mail either
        }
        else                                    # unknown (or -h)
        {
            print( "USAGE: $cmdhdr [-f|-h|-n|-s]\n" );
            print( "\t-f    force update\n" );
            print( "\t-h    this help screen\n" );
            print( "\t-n    no email\n" );
            print( "\t-s    print status only\n" );
            exit( $exitval );
        }
    }
}


###########################################################################
#   NAME: FileDump
#   DESC: reads the file and dumps as a string
#   ARGS: file to read
#   RTNS: contents of file as a string
###########################################################################
sub FileDump
{
    my $srcfile = $_[0];                        # src file
    my $rtn     = '';                           # init file content

    open( SRC, "<$srcfile" )                    # open src file or die (w/ msg)
      || SendMailMsg( 'Error', "$errhdr unable to read file at:\n$errspc '$srcfile'", 1, $nomail );
    $rtn = join( '', <SRC> );                   # read file into scalar
    close( SRC );                               # close src file

    return( $rtn );                             # return contents of src file
}


###########################################################################
#   NAME: SendMailMsg
#   DESC: send mail message (& exit)?
#   ARGS: subject, message, exit after prn/mail, prn
#   RTNS: n/a
###########################################################################
sub SendMailMsg
{
    my $subj = $_[0];                           # save subject
    my $msg  = $_[1];                           # save err msg
    my $exit = $_[2];                           # exit after prn/mail
    my $prn  = $_[3];                           # print

    if ( $prn )                                 # print
    {
        warn( "$msg\n" );
    }
    else                                        # mail
    {
        smtpmail::send_mail( "$mailadrs|$mailadrs|||$cmdhdr: $subj||$msg" );
    }

    exit( $exit ) if ( $exit );                 # exit if requested
}


###########################################################################
#   NAME: CleanSysMsg
#   DESC: pull out short & long message, rm HTML
#   ARGS: sys msg string
#   RTNS: short message string, long message string
###########################################################################
sub CleanSysMsg
{
    my @sysmsg = split( "\n", $_[0] );          # take sys msg and break on <CR>
    my $lrtn = '';                              # format long return string
    my $srtn = '';                              # format short return string

    foreach $line ( @sysmsg )                   # go thru sys msg lines
    {
                                                # parse sys msg line
        $line =~ /^\s*var\s+(\w+)essage\s*=\s*'(.*)';\s*$/;
        if ( $1 eq 'm' )                        # if long message
        {
            $lrtn = $2;                         # save long message
        }
        elsif ( $1 eq 'shortM' )                # if short message
        {
            $srtn = $2;                         # save short message
        }
    }

    $lrtn =~ s/<br>/\n    /iog;                 # change breaks to [CR]+indent
    $lrtn =~ s/\&nbsp;/ /og;                    # convert spaces
    $lrtn =~ s/^\s*(var)? message='//og;        # strip off leading JavaScript
    $lrtn =~ s/'\s*;\s*$//og;                   # strip off tailing JavaScript
    $lrtn =~ s/<\/?h\d[^>]*>//iog;              # rm header marks
    $lrtn =~ s/<hr>/\n\n/iog;                   # replace sep lines w/ [CR]
    $lrtn =~ s/<\/?table[^>]*>/\n/iog;          # replace table top/end w/ [CR]
    $lrtn =~ s/<\/?tr[^>]*>/\n/iog;             # replace table row w/ [CR]
    $lrtn =~ s/<\/?t[dh][^>]*>/  /iog;          # replace cells with indent
                                                # put links in parens after txt
    $lrtn =~ s/<a [^>]*href=["']([^"']+)["'][^>]*>([^<]+)<\/a>/$2 ($1)/ig;

    return( $srtn, $lrtn );                     # return reformatted strings
}


###########################################################################
#   NAME: WriteFile
#   DESC: writes text to the file
#   ARGS: file, text
#   RTNS: die on err
###########################################################################
sub WriteFile
{
    my $file = $_[0];                           # xml sys msg file
    my $msg  = $_[1];                           # system message

    open( OUT, ">$file" )                       # open xml sys msg file | die
      || SendMailMsg( 'Error', "$errhdr: unable to updated system message in: '$file'!", 1, $nomail );
    binmode( OUT );                             # write w/o ^M
    print( OUT $msg );                          # write new sys msg
    close( OUT );                               # close xml sys msg file
}


###########################################################################
#   NAME: GenRssStarter
#   DESC: creates text of an rss file that rest of script can populate
#   ARGS: file name
#   RTNS: rss-looking test
###########################################################################
sub GenRssStarter
{
    return( "<?xml version='1.0'?>
    <rss version='2.0'>
    <channel>
      <channel>
        <title>ClearQuest</title>
        <link>http://engrdocs.site/clearquest/index.html</link>
        <description>ClearQuest</description>
        <date>$gmtdate</date>
      </channel>
      <item/>
    </channel>
    </rss>" );
}


###########################################################################
#   NAME: Add2Rss
#   DESC: add the new system message to the RSS feed
#   ARGS: rss feed xml, short message, long message
#   RTNS: rss feed w/ new sys msg prepended
###########################################################################
sub Add2Rss
{
    my $rssfeed = $_[0];                        # existing rss feed
    my $newsmsg = $_[1];                        # short message
    my $newlmsg = $_[2];                        # long message
    my $newstr  = '';                           # init new string
    #my $datestr = GenTitleDateStr( $newmsg );   # get the date out of the str
    my $warning = $^W;                          # warnings en/disabled

    $newstr = "<item>\n"                        # create new rss item
            . "\t<title>$newsmsg</title>\n"
            . "\t<link>$downtime</link>\n"
            . "\t<description>$newlmsg</description>\n"
            . "\t<date>$gmtdate</date>\n"
            . "</item>\n";

    $^W = 0;                                    # don't look: disabling warnings
                                                # add new item before top post
    $rssfeed =~ s/((<item>)|<item\/?>)/$newstr$2/;
    $^W = $warning;                             # putting warnings back

    return( $rssfeed );                         # return rss feed w/ new item
}


###########################################################################
#   NAME: GenTitleDateStr
#   DESC: generate a date string for the rss title
#   ARGS: new system message
#   RTNS: short date string
###########################################################################
#sub GenTitleDateStr
#{
#    my $msg     = $_[0];                        # save new system message
#    my $mon     = '';                           # 3-char month
#    my $day     = '';                           # date
#    my @date    = ();                           # today's date
#    my $datestr = '';                           # today's m/dd
#
#                                                # find 3-char mon & date
#    $msg =~ /(Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day,?\s+([A-Z]\w\w)\w*\s+(\d+)/;
#    $mon = $2; $day = $3;                       # save off month & date
#
#    if ( !$mon || !$day )                       # problem with parsing
#    {
#        @date = gmtime( time() );               # get cur date, save mon, day
#        $datestr = sprintf( "%d/%02d", $date[4]+1, $date[3] );
#        return( $datestr );                     # return m/dd
#    }
#
#    return( "$mon $day" );                      # return 3-char month, day
#}
