#!/bin/sh
###########################################################################
#   NAME: secCXinst.sh
#   DESC: locks down the permissions on a CQ/XML install
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

CMDHDR=`basename $0`                            # basename, duh
NOBU=0                                          # default: backup enabled
SRCDIR=''                                       # source dir
BUCTR=0                                         # backup counter
CHOWNU='cqxmlusr'                                # chown user
CHOWNG='tools'                                  # chown tools
CQXILOGDIR='../cqxmllogs'                       # CQ/XML log dir

###########################################################################
#   NAME: PrnHelp
#   DESC: prints the help screen and exits
###########################################################################
PrnHelp()
{
    echo "DESC:  locks down the permissions on a CQ/XML install"
    echo "USAGE: $CMDHDR [-h|-nb] <dir>"
    echo "          -h      this help screen"
    echo "          -nb     \"no backup\" - don't backup source directory"
    echo "          dir     directory to secure"
    exit
}

for i in $*; do                                 # go thru cmd line args
    case $i in
        -h)     PrnHelp                         # need help
                ;;
        -nb)    NOBU=1                          # no backup
                ;;
        *)      if [ -d "$i" ]; then            # arg passed is dir
                    SRCDIR="$i"                 # save dir
                else
                    echo "$CMDHDR: ERROR - invalid directory '$i'!" >&2
                    PrnHelp
                fi
                ;;
    esac
done


if [ $NOBU -ne 1 ]; then                        # if backup not disabled
    while [ -d "$SRCDIR.$BUCTR" ]; do           # while backup dirs exist
        BUCTR=`expr $BUCTR + 1`                 # keep inc'ing the counter
    done

    echo "$CMDHDR: Archiving directory as '$SRCDIR.$BUCTR'..."
    mv $SRCDIR $SRCDIR.$BUCTR                   # rename src dir to backup dir
    mkdir $SRCDIR                               # make new dir w/ src name

    echo "$CMDHDR: Changing file ownership..."  # copy all the files
    (cd $SRCDIR.$BUCTR 2>/dev/null; tar -cf - *) | (cd $SRCDIR; tar -xf -)
fi

echo "$CMDHDR: Changing permissions..."         # fix permissions
find $SRCDIR      -type f              -exec chmod 400 {} \;
find $SRCDIR      -type f -name "*.pl" -exec chmod 500 {} \;
find $SRCDIR/data -type f              -exec chmod 600 {} \;
find $SRCDIR      -type d              -exec chmod 700 {} \;
chmod 300 $SRCDIR                               # disable browsing

if [ "`whoami`" = "root" ]; then                # if we're running as root
    echo "$CMDHDR: Changing ownership..."
                                                # find all & chown
    chown ${CHOWNU}:${CHOWNG} `find $SRCDIR -print`
fi

if [ ! -d "$SRCDIR/$CQXILOGDIR" ]; then                 # if log dir ! exist
    echo "$CHDHDR: Warning - unable to find log dir '$SRCDIR/$CQXILOGDIR'!" >&2
fi

echo "$CMDHDR: Complete!"
