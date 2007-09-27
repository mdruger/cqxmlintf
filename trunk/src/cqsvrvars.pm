###########################################################################
#   NAME: cqsvrvars.pm
#   DESC: hard-coded server variables
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
package CqSvr;                                  # as promised - our package name

### communication vars ####################################################
                                                # are we on Windows or not?
$osiswin    = defined( $ENV{OS} ) && $ENV{OS} =~ /^Windows/os ? 1 : 0;
$port       = 5556;                             # open tcp port
$tcpproto   = getprotobyname( 'tcp' );          # get protocol num for tcp
@mailerrto  = qw( cqsupport@mentor.com );          # mail errors to...

### filename vars #########################################################
                                                # CQ Perl on UNIX
$cqperl     = '/opt/rational/clearquest/bin/cqperl';
$filepre    = 'cqxi';                           # output file prefix
$livename   = "${filepre}_live.pl";             # live server
$queuename  = "${filepre}_queued.pl";           # queue manager
$logdir     = 'svrout';                         # log dir
$arcdir     = 'archive';                        # log archive dir
                                                # pub log parent dir based on os
$publogtop  = $osiswin                          # if on Win, use local dir
              ? defined( $main::cmddir ) && -d "$main::cmddir"
                ? "$main::cmddir"
                : '.'
              : '/opt';                         # !Win, use /opt
$publogdir  = "$publogtop/cqxmllogs";           # pub log dir
$ipqfile    = "$filepre.ipq_";                  # In Progress Queue file prefix
$qfile      = "$filepre.q_";                    # Queue file prefix
$lfile      = "$filepre.l_";                    # Live log prefix file
$qpubfile   = "${filepre}_q";                   # filename hdr of queue pub log
$lpubfile   = "${filepre}_l";                   # filename hdr of live pub log
$cqtanlog   = "${qfile}cqtan";                  # cqtan log
$encryptxml = "$main::cmddir/data/enckeys.xml"; # the encryption keys
$recmodxml  = "$main::cmddir/data/recmod.xml";  # record mod by ip
$sysmsgtxt  = "$main::cmddir/data/sysmsg.txt";  # system status message

### file attributes & contents ############################################
%filestat = ();                                 # file 'stat's
%modperms = ();                                 # modification permissions
%enckeys  = ();                                 # encryption keys
$sysmsg   = '';                                 # system message

### ClearQuest defaults ###################################################
                                                # default db/repo
%dbopts     = ( repo => 'repo', db => 'dev' );
#fix - wouldn't it be nice if recuk vals were arrays?
%recuk      = ( component => 'name',            # supported record uniq keys
                defect    => 'id',
                product   => 'name',
                query     => 'name',
                info      => 'type',
                note      => 'id',
                sql       => '',
                service_request => 'id',
              );
$waitnondef = 'yes';                            # wait non-default behavior
                                                # who can mod these rec types?
%modchkflds = ( component => ['responsible', 'product.responsible'],
                defect    => ['component.responsible', 'product.responsible', 'submitter', 'owner'],
                product   => ['responsible'],
                note      => [],
                service_request => [],
              );

### attributes ############################################################
                                                # <ClearQuest> attributes
@cqatrbs    = qw( login password encrypted db repo cqtan email-fail );
                                                # record attribute defaults
%recatrbdef = ( component => {action => 'view'},
                defect    => {action => 'view'},
                product   => {action => 'view'},
                query     => {},
                info      => {},
                note      => {action => 'view'},
                service_request => {action => 'view'},
              );
                                                # field attribute defaults
%fldatrbs   = ( component => {behavior => 'replace'},
                defect    => {behavior => 'replace'},
                product   => {behavior => 'replace'},
                query     => {operator => 'equals'},
                info      => {},
                note      => {},
                service_request => {},
              );
                                                # non-standard record attributes
%recatrbs   = ( component => [ 'action' ],
                defect    => [ 'action' ],
                product   => [ 'action' ],
                query     => [ ],
                info      => [ 'dynamic', 'record' ],
                note      => [ 'action' ],
                service_request => [ 'action' ],
              );
                                                # query rtn attributes
%queryatrb  = ( counter => 'row', rectype => 'rectype' );

### exceptions ############################################################
@recswoatrbs = ( 'sql' );                       # records w/o attributes
@recswoactions = qw( info query sql );          # records w/o actions

### strings ###############################################################
$rootelem   = 'ClearQuest';                     # root element
$commroot   = 'CqComm';                         # communication root elem
$qelempre   = 'cq';                             # queued element prefix
$atrbkey    = 'attributes';                     # attributes key
$errstr     = 'ERROR';                          # standard error string
$rtnleadspc = '  ';                             # leading space for rtn XML
$promptelem = 'prompt';                         # prompt element string
$enckeyroot = 'Encrypt';                        # encryption element root string
$encipelem  = 'iplist';                         # encryption ip element string
$encusrelem = 'userlist';                       # encryption user element string
$recmodroot = 'IpRecMod';                       # ip-based record mod root str
$runswitch  = '-r';                             # run num switch
$sysswitch  = '-s';                             # multi-system switch
                                                # on UNIX cqperl resolves to...
$execstrre  = '/opt/rational/clearquest/\w+/bin/\.\./\.\./\.\./common/\w+/bin/ratlperl';
$mailerrsubj = 'CQ/XML Interface Server Error'; # subject of email error
$cpenvlang  = 'en_US.UTF-8';                    # Code Page aka $ENV{LANG}
                                                # license server redundancy
$licenv     = '1717@licsvr03:1717@licsvr02:1717@licsvr01';
                                                # permissions failure
$permerr    = 'client machine does not have permissions to modify record';
$sysmsghdr  = 'SYSTEM STATUS ALERT';            # system status message header
%dbtypes    = (
                'cqdevdb' => 'development',
                'cqqa01' => 'qa',
                'cqqa02' => 'qa',
                'cqqa03' => 'qa',
                'cqqa04' => 'qa',
                'cqtestdb'  => 'test',
                'cqproddb'  => 'production',
                'cqprodrodb'  => 'production read-only',
              );

1;
