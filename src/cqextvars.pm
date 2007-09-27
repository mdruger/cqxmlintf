###########################################################################
#   NAME: cqextvars.pm
#   DESC: hard-coded ClearQuest variables
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
package CqExt;                                  # as promised - our package name
use CQPerlExt;                                  # use CQ Perl libraries

### query operators #######################################################
                                                # operator to CQ enum const
%op2cq      = ( 'equals'                   => $CQPerlExt::CQ_COMP_OP_EQ,
                'does not equal'           => $CQPerlExt::CQ_COMP_OP_NEQ,
                'less than'                => $CQPerlExt::CQ_COMP_OP_LT,
                'less than or equal to'    => $CQPerlExt::CQ_COMP_OP_LTE,
                'greater than'             => $CQPerlExt::CQ_COMP_OP_GT,
                'greater than or equal to' => $CQPerlExt::CQ_COMP_OP_GTE,
                'contains'                 => $CQPerlExt::CQ_COMP_OP_LIKE,
                'does not contain'         => $CQPerlExt::CQ_COMP_OP_NOT_LIKE,
                'between'                  => $CQPerlExt::CQ_COMP_OP_BETWEEN,
                'not between'              => $CQPerlExt::CQ_COMP_OP_NOT_BETWEEN,
                'is null'                  => $CQPerlExt::CQ_COMP_OP_IS_NULL,
                'is not null'              => $CQPerlExt::CQ_COMP_OP_IS_NOT_NULL,
                'in'                       => $CQPerlExt::CQ_COMP_OP_IN,
                'not in'                   => $CQPerlExt::CQ_COMP_OP_NOT_IN,
              );

### workspace query types #################################################
%wsqt = ( 'Personal Queries' => $CQPerlExt::CQ_WKSPC_USER_QUERIES,
          'Public Queries'   => $CQPerlExt::CQ_WKSPC_SYSTEM_QUERIES,
          'All Queries'      => $CQPerlExt::CQ_WKSPC_BOTH_QUERIES,
        );
%wsqt = ( 'Personal Queries' => 2,              # doc'd constants don't work!
          'Public Queries'   => 1,
          'All Queries'      => 3,
        );

1;
