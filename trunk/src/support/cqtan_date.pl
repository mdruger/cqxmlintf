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

print( "\nPerl's day of the year:\n" );
printf( "  GMT:   %03d\n", (gmtime( time() ))[7] );
printf( "  Local: %03d\n", (localtime( time() ))[7] );
print( "\n" );
