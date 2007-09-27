#!/bin/sh
###########################################################################
#   NAME: cp2svr.sh
#   DESC: copies CQ/XML Interface files
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
#   user globals
###########################################################################
DESTDIR='//ace/ce_svr/ChangeManagement/Interface/cqxmlintf/release'
SVRAPPS='cqxi_live.pl cqxi_queued.pl'
SVRINC='cqext.pm cqextvars.pm cqsvrfuncs.pm cqsvrvars.pm cqxml.pm cqflds.pm cqsys.pm'
SUPPORT='support/clnTmp2PubLogs.pl support/cprls2svr.pl support/cqxi_chklive.pl support/crontab.txt support/secCXinst.sh'

###########################################################################
#   script globals
###########################################################################
ERRHDR="`basename $0`: ERROR -"                 # error header string
DISPCOL1=37                                     # column #1 width
NXTARG=''                                       # next arg worth having tmp var
COPYFLAG=0                                      # copy the file or not

###########################################################################
#   parse cmd line
###########################################################################
for i in $*; do                                 # go thru cmd line args
    case $i in
        -d) NXTARG=d                            # next arg is dir
            ;;
                                                # if next arg is dir
        *)  if [ -n "$NXTARG" -a "$NXTARG" = "d" ]; then
                if [ -d "$i" ]; then            # if dir is okay
                    DESTDIR=$i                  # save alt dir
                    NXTARG=''                   # unset next arg flag
                else                            # bad dir
                    echo "$ERRHDR - invalid directory '$i'!" >&2
                    exit 1
                fi
            else                                # unknown arg
                echo "USAGE: cp2svr.sh [-d <dir>|-h]"
                echo "          -d <dir>  copy to alternate directory"
                echo "          -h        this help screen"
                exit
           fi
           ;;
    esac
done

echo ""

###########################################################################
#   NAME: CpSubDir
#   DESC: 
#   ARGS: 
#   RTNS: 
###########################################################################
CpSubDir()
{
    printf "    %-${DISPCOL1}s " "$1/"          # prn '<subdir>/'
    if [ ! -d "$DESTDIR/$1" ]; then             # if subdir doesn't exist
        echo "copying - \c"                     # say we're going to cp
                                                # use tar to cp dir structure
        tar -cf - $1/* | (cd $DESTDIR >NUL; tar -xf -)
    else                                        # subdir parser exists
        echo "same"                             # assume it's okay
    fi
}


###########################################################################
#   check and copy sub dirs
###########################################################################
CpSubDir XML
CpSubDir Crypt
CpSubDir data

###########################################################################
#   diff and copy src
###########################################################################
for FILE in $SVRAPPS $SVRINC $SUPPORT; do       # go thru file list
    COPYFLAG=0                                  # reset copy flag
    FILEDEST=`echo $FILE | sed "s,^.*/,,"`      # file destination
    printf "    %-${DISPCOL1}s " $FILE          # prn file name
    if [ -f "$DESTDIR/$FILEDEST" ]; then        # if file already exists
        cmp -s $FILE $DESTDIR/$FILEDEST         # compare src & dest file
        if [ $? -eq 0 ]; then                   # files are the same
            echo "same"                         # just say so
        elif [ $? -eq 1 ]; then                 # files differ
            echo "overwrite? [y|N]: \c"         # prompt for overwrite
            COPYFLAG=1                          # set copy flag
        else                                    # comparison error
            echo "error"                        # throw error
        fi
    else                                        # new file
        echo "new"                              # say so
        COPYFLAG=1                              # set copy flag
    fi
    if [ $COPYFLAG -eq 1 ]; then                # if copy this file
        cp -i $FILE $DESTDIR/$FILEDEST 2>NUL    # copy with prompt
        if [ $? -ne 0 ]; then                   # if error copying
            echo "$ERRHDR unable to copy '$FILE' to '$DESTDIR/$FILEDEST'!" >&2
            exit 1
        fi
    fi
done
echo ""
