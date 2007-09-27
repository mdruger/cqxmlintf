###########################################################################
#   NAME: cqflds.pm
#   DESC: functions for special ClearQuest field magic
#   PKG:  CqFld
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
#   field dependency reference
###########################################################################
# RECORD     PARENT                      CHILD
# ---------  -------------------------   ----------------------------------
# Defect     component                   comp_spec_label[1-5]
#                                        component.comp_field[1-5]_mandatory
#                                        owner
#                                        target_processor
#            platform_os                 platform_os_ver
#                                        platform_proc
#            platform_os_ver             platform_proc
#            platform_validated_os       platform_validated_os_ver
#                                        platform_validated_proc
#            platform_validated_os_ver   platform_validated_proc
#            product                     comp_spec_label[1-5]
#                                        component
#                                        customer_company
#                                        planned_release_list
#                                        prod_spec_label[1-20]
#                                        product.prod_field[1-20]_mandatory
#                                        product_field1_label
#                                        product_field[6-20]
#                                        target_processor
#                                        version_fixed
#                                        version_reported
#                                        version_type_reported
#                                        version_validated
#            show_all_users              owner
#                                        submitter
#            version_type_fixed          version_fixed
#            version_type_reported       version_reported
#            version_type_validated      version_validated
# ---------  -------------------------   ----------------------------------
# Component  approve                     approved
#                                        validated
# ---------  -------------------------   ----------------------------------
# Product    approve                     approved
#                                        validated
###########################################################################

###########################################################################
#   package globals
###########################################################################
                                                # field order dependencies
my %order = ( defect =>     { product                   => 0,
                              component                 => 1,
                              show_all_users            => 2,
                              platform_os               => 3,
                              platform_os_ver           => 4,
                              platform_validated_os     => 5,
                              platform_validated_os_ver => 6,
                              version_type_reported     => 7,
                              version_type_fixed        => 8,
                              version_type_validated    => 9,
                            },
              product =>    { },
              component =>  { },
              version_control => { },
            );


###########################################################################
#   NAME: Order
#   DESC: given a record type & a list of fields, return the fields in the
#         order required to get the dependencies correct
#   ARGS: record type, fields
#   RTNS: fields in order
#   NOTE: if you set a array index directly, Perl automatically fills in
#         the array with NULL values so the array is complete
###########################################################################
sub Order
{
    my $rectype = shift( @_ );                  # record type
    my @ordered = ();                           # ordered fields
    my @noorder = ();                           # the rest of the fields

    if ( !defined( $order{$rectype} ) )         # if bad record type
    {
        warn( "ERROR: invalid record type '$rectype' passed to ", (caller( 0 ))[3] , "()!\n" );
        return();
    }

    foreach $field ( @_ )                       # go thru passed fields
    {
                                                # if its order is important
        if ( defined( ${$order{$rectype}}{$field} ) )
        {
                                                # add it to our ordered array
            $ordered[${$order{$rectype}}{$field}] = $field
        }
        else                                    # order doesn't matter
        {
            push( @noorder, $field );           # save it for later
        }
    }
                                                # rtn !null ordered vals & rest
    return( grep( defined( $_ ), @ordered ), @noorder );
}
