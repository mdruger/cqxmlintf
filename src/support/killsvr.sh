#!/bin/sh
###########################################################################
#   NAME: killsvr.sh
#   DESC: kills the cqperl process properly
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

CQPPROCS=`ps -o pid,ppid,args | grep cqperl | grep -v grep | sed "s/^  *\([0-9][0-9]*\)  *\([0-9][0-9]*\)  *.*$/\1,\2/"`
for i in $CQPPROCS; do
    if [ -z "$CPROC1" ]; then
        CPROC1=`echo $i | cut -d, -f1`
        PPROC1=`echo $i | cut -d, -f2`
    else
        CPROC2=`echo $i | cut -d, -f1`
        PPROC2=`echo $i | cut -d, -f2`
    fi
done

if [ $CPROC1 -eq $PPROC2 ]; then
    kill -9 $CPROC2
else
    kill -9 $CPROC1
fi
