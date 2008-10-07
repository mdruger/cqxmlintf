###########################################################################
#   NAME: cqext.pm
#   DESC: functions for performing ClearQuest operations
#   PKG:  CQ
#   NOTE: you must wrap every CQ call with an eval{} so a failure in CQ
#         doesn't kill the entire script
#   NOTE: requires cqperl or ratlperl
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
package CQ;                                     # package named "CQ"
use CQPerlExt;                                  # need all the CQ junk
require( 'cqflds.pm' );                         # field order
require( 'cqextvars.pm' );                      # ClearQuest variables
require( 'cqsvrfuncs.pm' );                     # cq svr functions
require( 'cqsys.pm' );                          # sys-lvl functions

###########################################################################
#   package globals
###########################################################################
my $sessionref = 'CQSession';                   # session obj ref
my $entityref  = 'CQEntity';                    # entity obj ref
$debug = 0;                                     # init pkg'd debug var


###########################################################################
#   NAME: Login
#   DESC: logs-in to the database
#   ARGS: login, password, db, repo, cqtan
#   RTNS: err status, session object
###########################################################################
sub Login
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $login   = $_[0];                        # login
    my $pswd    = $_[1];                        # password
    my $db      = $_[2];                        # database
    my $repo    = $_[3];                        # repository
                                                # NEED cq transaction number
    my $cqtan   = $_[4] || return( 'invalid source transaction number!' );
    my $session = undef;                        # init cq session obj
    my $err     = '';                           # error message

    eval{ $session = CQSession::Build() };      # build a CQ session
    return( "unable to create session object!" ) if ( $@ || ref( $session ) ne $sessionref );
                                                # login as user
    eval{ $session->UserLogon( $login, $pswd, $db, $repo ) };
    return( "unable to login as '$login'!" ) if ( $@ );
                                                # CYA var to save into hist
    eval{ $session->SetNameValue( 'ActionSrc', "$cqtan" ) };
    return( "unable to set session variable!" ) if ( $@ );

    return( $err, $session );                   # rtn err stat & session obj
}


###########################################################################
#   NAME: Logout
#   DESC: logs out a CQ session
#   ARGS: CQ session obj to logout
#   RTNS: n/a
###########################################################################
sub Logout
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    eval{ CQSession::Unbuild( $_[0] ) };        # logout
}


###########################################################################
#   NAME: Dump
#   DESC: returns ALL field values for a given record
#   ARGS: session obj, record type, record id
#   RTNS: err status, hash of all record vals (fld=>val)
###########################################################################
sub Dump
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session = $_[0];                        # session obj
    my $type    = $_[1];                        # record type
    my $id      = $_[2];                        # record id
    my $entity  = undef;                        # entity obj
    my @fldlist = ();                           # field list
    my $err     = '';                           # error message
    my %rtn     = ();                           # init return hash

                                                # get the record
    eval{ $entity = $session->GetEntity( "$type", "$id" ) };
    return( "unable to retrieve '$type' record: '$id'!" ) if ( $@ || ref( $entity ) ne $entityref );
                                                # get all fields for record
    eval{ @fldlist = @{$entity->GetFieldNames()} };
    return( "unable to retrieve fields for $type record '$id'!" ) if ( $@ );

    foreach $field ( @fldlist )                 # go thru field list
    {
                                                # save name=>val to rtn hash
        eval{ $rtn{$field} = $entity->GetFieldValue( $field )->GetValue() };
        return( "unable to retrieve '$field' field for $type record '$id'!" ) if ( $@ );
    }

    return( $err, %rtn );                       # return name=>val hash
}


###########################################################################
#   NAME: View
#   DESC: returns the specified field values for a given record
#   ARGS: session obj, record type, record id, fields to rtn
#   RTNS: error status, hash of record vals (fld=>val)
###########################################################################
sub View
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session = shift( @_ );                  # session obj
    my $type    = shift( @_ );                  # record type
    my $id      = shift( @_ );                  # record id
    my @fldlist = @_;                           # fields to view
    my $entity  = undef;                        # entity obj
    my $err     = '';                           # error message
    my %rtn     = ();                           # init return hash

                                                # get the record
    eval{ $entity = $session->GetEntity( "$type", "$id" ) };
    return( "unable to retrieve '$type' record: '$id'!" ) if ( $@ || ref( $entity ) ne $entityref );
    foreach $field ( @fldlist )                 # go thru passed fields
    {
                                                # save field=>val into hash
        eval{ $rtn{$field} = $entity->GetFieldValue( $field )->GetValue() };
        return( "unable to retrieve '$field' field for $type record '$id'!" ) if ( $@ );
    }

    return( $err, %rtn );                       # return field=>val hash
}


###########################################################################
#   NAME: Submit
#   DESC: submits a record
#   ARGS: session obj, record type, field=>{value=>behavior}
#   RTNS: error status, id
###########################################################################
sub Submit
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session = shift( @_ );                  # session obj
    my $type    = shift( @_ );                  # record type
    my %fields  = @_;                           # fields to set at submit
    my $entity  = undef;                        # entity object
    my $err     = '';                           # error message
    my $id      = '';                           # init return id

                                                # create a record/entity
    eval{ $entity = $session->BuildEntity( "$type" ) };
    return( SaveOrFail( $entity, "unable to create '$type' record!" ) )
      if ( $@ || ref( $entity ) ne $entityref );

    eval{ $id = $entity->GetDisplayName() }     # save record id
                                                #  unless err w/ (fields | save)
      unless ( $err = SaveOrFail( $entity, SetFields( $entity, $type, %fields ) ) );

    return( $err, $id );                        # return err stat & id
}


###########################################################################
#   NAME: Action
#   DESC: performs an action on a record
#   ARGS: permissions, session obj, record type, record id, action,
#         field=>{value=>behavior}
#   RTNS: error status (null = ok)
###########################################################################
sub Action
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $perms   = shift( @_ );                  # permissions based on ip
    my $session = shift( @_ );                  # session obj
    my $type    = shift( @_ );                  # record type
    my $id      = shift( @_ );                  # record id
    my $action  = shift( @_ );                  # action name
    my %fields  = @_;                           # field=>[value, behavior]
    my $entity  = undef;                        # entity obj

                                                # get the record
    eval{ $entity = $session->GetEntity( "$type", "$id" ) };
    return( SaveOrFail( $entity, "unable to retrieve '$type' record: '$id'!" ) )
      if ( $@ || ref( $entity ) ne $entityref );
    return( SaveOrFail( $entity, "$CqSvr::permerr '$id'!" ) ) if ( %{$perms} && !ChkPerms( $session, $entity, $type, %{${$perms}{$type}} ) );
    eval{ $entity->EditEntity( "$action" ) };   # perform action on record
    return( SaveOrFail( $entity, "unable to perform the '$action' action on the $type record '$id'!" ) ) if ( $@ );
                                                # rtn success or err msg
    return( SaveOrFail( $entity, %fields ? SetFields( $entity, $type, %fields ) : '' ) );
}


###########################################################################
#   NAME: ChkPerms
#   DESC: checks if the current user has permissions to update the record
#   ARGS: session, entity, rec type, ip perms for type
#   RTNS: 0 on failure, 1 on success
###########################################################################
sub ChkPerms
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session  = shift( @_ );                 # session obj
    my $entity   = shift( @_ );                 # entity obj
    my $type     = shift( @_ );                 # record type
    my %perms    = @_;                          # perms for this ip/type
    my $fldval   = '';                          # field value
    my $curuser  = '';                          # current user
    my @permflds = @{$CqSvr::modchkflds{$type}}; # permission fields for type
    my @fldvals  = ();                          # field values

    foreach $field ( keys( %perms ) )           # go thru ip perm fields
    {
                                                # get field for this record
        eval{ $fldval = $entity->GetFieldValue( $field )->GetValue() };
                                                # if field val = ip map
        return( 1 ) if ( grep( /^$fldval$/, @{$perms{$field}} ) );
    }
                                                # get user name
    eval{ $curuser = $session->GetUserLoginName() };
    return( 0 ) if ( $@ );                      # return 0 if prob getting user

                                                # go thru perm fields in order
    for ( my $i=0; defined( $permflds[$i] ); $i++ )
    {
                                                # get perm field val
        eval{ @fldvals = @{$entity->GetFieldValue( $permflds[$i] )->GetValueAsList()} };
                                                # return success if user matches
        return( 1 ) if ( grep( /^$curuser$/, @fldvals ) );
    }
    
    return( 0 );                                # got this far?, return fail
}


###########################################################################
#   NAME: SetFields
#   DESC: sets a bunch of fields
#   ARGS: entity obj, record type, field=>{value=>behavior}
#   RTNS: null on success, error message on failure
#   NOTE: DeleteFieldValue() will remove the val from a non-ref-list if the
#         passed value matches the value in the field
###########################################################################
sub SetFields
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $entity = shift( @_ );                   # save entity obj
    my $type = shift( @_ );                     # record type
    my %fields = @_;                            # save fld=>val=>behav hash
    my $err = '';                               # init err msg

                                                # go thru fields (in cq order)
    foreach $field ( CqFlds::Order( $type, keys( %fields ) ) )
    {
                                                # go thru field values
        foreach $fldval ( keys( %{$fields{$field}} ) )
        {
                                                # if behav = 'add'
            if ( ${$fields{$field}}{$fldval} eq 'add' )
            {
                                                # 
                $err = AddFieldVal( $entity, $field, $fldval );
                return( "$err" ) if ( $err );   # 
            }
                                                # 
            elsif ( ${$fields{$field}}{$fldval} eq 'remove' )
            {
                eval{ $err = $entity->DeleteFieldValue( $field, $fldval ) };
                return( $err ) if ( $err = ChkRtn( $err, $@ ) );
            }
            else                                # replace
            {
                                                # set field & save err
                eval{ $err = $entity->SetFieldValue( $field, $fldval ) };
                                                # rtn err if problem
                return( $err ) if ( $err = ChkRtn( $err, $@ ) || ChkSetVal( $entity, $field, $fldval ) );
            }
        }
    }

    return( $err );                             # if we got here, return ok
}


###########################################################################
#   NAME: AddFieldVal
#   DESC: adds values to ref-lists, ml-strs or int fields
#   ARGS: entity obj, field name, field value
#   RTNS: err on failure, null on success
###########################################################################
sub AddFieldVal
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $entity = $_[0];                         # entity object
    my $fldname = $_[1];                        # field name
    my $fldval = $_[2];                         # field value
    my $fldtype = undef;                        # field type
    my $curfldval = '';                         # current field value
    my @curfldlist = ();                        # current field value as list
    my $rtn = '';                               # return str

                                                # get field type | rtn err
    eval{ $fldtype = $entity->GetFieldType( $fldname ) };
    return( "unable to retrieve '$fldname' field information" ) if ( $@ );

                                                # if field is ref-list
    if ( $fldtype == $CQPerlExt::CQ_REFERENCE_LIST )
    {
                                                # get val of cur list
        eval{ @curfldlist = @{$entity->GetFieldValue( $fldname )->GetValueAsList()}; };
                                                # skip if no err but val exists
        return( $rtn ) if ( !$@ && grep( /^$fldval$/, @curfldlist ) );
                                                # use AddFieldValue()
        eval{ $rtn = $entity->AddFieldValue( $fldname, $fldval ) };
        return( "unable to add '$fldval' to the '$fldname' field" ) if ( $rtn || $@ );
        return( $rtn ) if ( $rtn = ChkSetVal( $entity, $fldname, $fldval ) );
    }
                                                # if field is multi-line string
    elsif ( $fldtype == $CQPerlExt::CQ_MULTILINE_STRING )
    {
                                                # get current value | rtn err
        eval{ $curfldval = $entity->GetFieldValue( "$fldname" )->GetValue() };
        return( "unable to retrieve '$fldname' field value" ) if ( $@ );
        $curfldval = '' if ( !$curfldval );     # init if fld val is null
                                                # join vals & set field
        eval{ $rtn = $entity->SetFieldValue( $fldname, $curfldval . $fldval ) };
                                                # rtn err if problem
        return( $rtn ) if ( $rtn = ChkRtn( $rtn, $@ ) );
    }
    elsif ( $fldtype == $CQPerlExt::CQ_INT )    # if field is integer
    {
                                                # rtn err if val is not a num
        return( "the '$fldname' field requires an integer" ) if ( $fldval !~ /^\d+$/ );
                                                # get current value | rtn err
        eval{ $curfldval = $entity->GetFieldValue( "$fldname" )->GetValue() };
        return( "unable to retrieve '$fldname' field value" ) if ( $@ );
        $curfldval = 0 if ( !$curfldval );      # init 0 if fld val is null
                                                # add vals & set field
        eval{ $rtn = $entity->SetFieldValue( $fldname, $curfldval + $fldval ) };
                                                # rtn err if problem
        return( $rtn ) if ( $rtn = ChkRtn( $rtn, $@ ) );
    }
    else                                        # some other field type
    {
        $rtn = "the '$fldname' field does not support the 'add' behavior";
    }

    return( $rtn );                             # return err str | null
}


###########################################################################
#   NAME: ChkRtn
#   DESC: checks the different return values and save to one var
#   ARGS: error values to check
#   RTNS: value of last error value
###########################################################################
sub ChkRtn
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $rtnerr = 0;                             # init ok rtn

    foreach $err ( @_ )                         # go thru errs
    {
                                                # if err & > prev saved err
        $rtnerr = $err if ( $err && $err gt $rtnerr );
    }
                                                # strip out perl line from err
    $rtnerr =~ s/\. at \w:\/[\w\/ \.]+ line \d+\.\s*$/./;

    return( $rtnerr );                          # rtn err or nothing
}


###########################################################################
#   NAME: ChkSetVal
#   DESC: checks val set/added to field
#   ARGS: entity obj, field name, new val
#   RTNS: err on failure, null on success
#   NOTE: we can't use a query here because we're not sure what the unique
#         key column name is and if it's a multi-part key we can't parse
#         the key to split it into columns (ex: "Release 1a IT")
###########################################################################
sub ChkSetVal
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $entity  = $_[0];                        # entity object
    my $fldname = $_[1];                        # field name
    my $fldval  = $_[2];                        # field value
    my $errmsg  = "unable to set $fldname field to '$fldval'";
    my $err     = '';                           # err rtn from cq
    my $session = undef;                        # session obj
    my $entdef  = undef;                        # entity def obj
    my $fldtype = undef;                        # field type obj
    my $tmpent  = undef;                        # tmp entity obj

                                                # check validity of field val
    #eval{ $err = $entity->GetFieldValue( $fldname )->ValidityChangedThisSetValue(); };
    #return( $errmsg ) if ( ChkRtn( $err, $@ ) ); # chk rtn of ValChgThisSetVal()

    eval
    {
        $session = $entity->GetSession();       # gen session obj of cur session
                                                # create entitydef obj
        $entdef = $session->GetEntityDef( $entity->GetEntityDefName() );
                                                # get field type
        $fldtype = $entdef->GetFieldDefType( $fldname );
    };
    return( $errmsg ) if ( $@ );                # rtn err msg if cq failure
                                                # if field is ref | ref-list
    if ( $fldtype == $CQPerlExt::CQ_REFERENCE || $fldtype == $CQPerlExt::CQ_REFERENCE_LIST )
    {
        eval{ $tmpent = $session->GetEntity( $entdef->GetFieldReferenceEntityDef( $fldname )->GetName(), "$fldval" ); };
        return( $errmsg ) if ( $@ );            # rtn err msg if cq failure
    }

    return( '' );                               # explicitly return nothing
}


###########################################################################
#   NAME: SaveOrFail
#   DESC: tries to commit the record or fail
#   ARGS: entity object (err message)
#   RTNS: null on success, err str on failure
###########################################################################
sub SaveOrFail
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $entity = $_[0];                         # entity obj
    my $err    = $_[1] ? $_[1] : '';            # use passed err | default=ok

                                                # validate the record w/o err
    eval{ $err = $entity->Validate() } unless( $err );
    if ( $err = ChkRtn( $err, $@ ) )            # if prob w/ validate
    {
        eval{ $entity->Revert() };              # revert record
    }
    else                                        # validate ok
    {
        eval{ $err = $entity->Commit() };       # commit record
        $err = ChkRtn( $err, $@ );              # save err, if any
    }

    return( $err );                             # return empty or err str
}


###########################################################################
#   NAME: Delete
#   DESC: deletes the given record
#   ARGS: session object, record type, record id
#   RTNS: err msg on failure, null on success
###########################################################################
sub Delete
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session = $_[0];                        # session obj
    my $type    = $_[1];                        # record type
    my $id      = $_[2];                        # record id
    my $entity  = undef;                        # entity object
    my $err     = '';                           # error message

                                                # get the record
    eval{ $entity = $session->GetEntity( "$type", "$id" ) };
    return( "unable to find $type record: '$id'!" ) if ( $@ );
    eval{ $err = $session->DeleteEntity( $entity, 'Delete' ) };
    return( "unable to delete $type record: '$id'!" ) if ( $@ || $err );

    return( $err );                             # return error status
}


###########################################################################
#   NAME: Query
#   DESC: runs a user-specified cq query w/ user options
#   ARGS: session obj, user login, query name, filters (field=>{value=>logic})
#   RTNS: error status, array of query vals [{fld=>val},]
###########################################################################
sub Query
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session = shift( @_ );                  # session object
    my $login   = shift( @_ );                  # user login
    my $query   = shift( @_ );                  # query name
    my %filters = @_;                           # query prompted filters/logic

    my $err       = '';                         # init err rtn str
    my $querydef  = undef;                      # querydef object
    my $resultset = undef;                      # query result set object
    my @rtn       = ();                         # init rtn array
                                                # create query def obj
    ($err, $querydef) = GetQueryDefObj( $session, $login, $query );
    return( $err ) if ( $err );
                                                # add extra fields to query
    ($err, $querydef) = AddFields2Query( $query, $querydef, keys( %filters ) );
    return( $err ) if ( $err );
                                                # add in the prompt values
    ($err, $resultset) = AddQueryPrompts( $query, $session, $querydef, %filters );
    return( $err ) if ( $err );
                                                # fix SQL for login
    ($err, $resultset) = FixQueryCurUsr( $query, $session, $querydef, $resultset, $login );
    return( $err ) if ( $err );
                                                # gen query output & save
    ($err, @rtn) = QueryOutput( $query, $resultset, $querydef );
    return( $err ) if ( $err );

    return( $err, @rtn );                       # return query output
}


###########################################################################
#   NAME: GetQueryDefObj
#   DESC: builds a querydef object
#   ARGS: session obj, login, query name
#   RTNS: err, querydef obj
###########################################################################
sub GetQueryDefObj
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session = $_[0];                        # session obj
    my $login   = $_[1];                        # user's login
    my $query   = $_[2];                        # query name

    my $workspc = undef;                        # init workspace object

    eval{ $workspc = $session->GetWorkSpace() }; # create workspace object
    return( "unable to create query workspace!" ) if ( $@ );
                                                # get query definition
    eval{ $querydef = $workspc->GetQueryDef( $query ) };
    return( "unable to retrieve query '$query'!" ) if ( $@ );

    return( '', $querydef );                    # rtn no err & good querydef obj
}


###########################################################################
#   NAME: AddFields2Query
#   DESC: adds "extra" fields to a query's select
#   ARGS: query name, querydef obj, fields to add
#   RTNS: err, querydef obj
###########################################################################
sub AddFields2Query
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $query    = shift( @_ );                 # query name
    my $querydef = shift( @_ );                 # querydef obj
    my @fields   = @_;                          # fields to add

                                                # go thru non-prompt fields
    foreach $addfld ( grep( !/^$CqSvr::promptelem\d+$/, @fields ) )
    {
                                                # add field to query def
        eval{ $querydef->BuildField( $addfld ) };
        return( "unable to add field '$addfld' to '$query' query!" ) if ( $@ );
    }

    return( '', $querydef );                    # rtn no err, querydef obj
}


###########################################################################
#   NAME: AddQueryPrompts
#   DESC: add prompt values to a query
#   ARGS: query name, session obj, querydef obj, filters hash
#   RTNS: err, resultset obj
###########################################################################
sub AddQueryPrompts
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $query    = shift( @_ );                 # query name
    my $session  = shift( @_ );                 # session obj
    my $querydef = shift( @_ );                 # querydef obj
    my %filters  = @_;                          # prompt values

    my $resultset = undef;                      # init resultset obj
    my $promptctr = 0;                          # prompts counter
    my $fldtype   = 0;                          # field type
    my $prevop    = '';                         # previous operator tmp var
    my $curop     = '';                         # current operator tmp var
    my $fmtval    = '';                         # reformatted val

                                                # build the result set object
    eval{ $resultset = $session->BuildResultSet( $querydef ) };
    return( "unable to build query '$query'!" ) if ( $@ );
                                                # get number of prompts
    eval{ $promptctr = $resultset->GetNumberOfParams(); };
    return( "unable to parameterize query '$query'!" ) if ( $@ );
    if ( %filters )                             # if filters passed
    {
        for ( my $i=1; $i<=$promptctr; $i++ )   # go thru prompts
        {
                                                # if prompt specified
            if ( defined( $filters{"$CqSvr::promptelem$i"} ) )
            {
                                                # go thru specified values
                foreach $val ( keys( %{$filters{"$CqSvr::promptelem$i"}} ) )
                {
                    $fmtval = $val;             # save formatted val real quick
                    eval{ $fldtype = $resultset->GetParamFieldType( $i ); };
                    return( "unable to determine '$CqSvr::promptelem$i' field type!" ) if ( $@ );
                    if ( $fldtype == $CQPerlExt::CQ_DATE_TIME && $val =~ /^\[\w+\]$/ )
                    {
                        $fmtval = FixDate( lc( $val ) );
                        return( "unable to resolve '$CqSvr::promptelem$i' date!" ) if ( !$val );
                    }
                                                # add the value as query param
                    eval{ $resultset->AddParamValue( $i, $fmtval ); };
                    return( "unable to add '$CqSvr::promptelem$i' value '$val'!" ) if ( $@ );
                                                # if operator specified
                    if ( defined( ${$filters{"$CqSvr::promptelem$i"}}{$val} )
                         && ${$filters{"$CqSvr::promptelem$i"}}{$val} )
                    {
                        $curop = lc( ${$filters{"$CqSvr::promptelem$i"}}{$val} );
                                                # if valid operator
                        if ( defined( $CqExt::op2cq{$curop} ) )
                        {
                                                # save operator
                            $curop = $CqExt::op2cq{$curop};
                        }
                        else                    # invalid operator
                        {
                                                # throw error
                            return( "unknown query operator '" . ${$filters{"$CqSvr::promptelem$i"}}{$val} . "' for '$CqSvr::promptelem$i'!" );
                        }
                    }
                    else                        # no operator specified
                    {
                                                # use default operator
                        $curop = $CqExt::op2cq{${$CqSvr::fldatrbs{query}}{operator}};
                    }
                                                # if 1st time | flds ops match
                    if ( !$prevop || $curop eq $prevop )
                    {
                                                # add op as query param op
                        eval{ $resultset->SetParamComparisonOperator( $i, $curop ); };
                        $prevop = $curop;       # save cur op as prev op
                    }
                    else                        # 1 flds has >1 op
                    {
                                                # throw error
                        return( "conflicting operators specified for '$CqSvr::promptelem$i'!" );
                    }
                }
                $prevop = '';                   # re-init prev op var
            }
        }
    }

    return( '', $resultset );                   # rtn err & resultset obj
}


###########################################################################
#   NAME: FixDate
#   DESC: converts the 3 special CQ dates to real dates
#   ARGS: date value
#   RTNS: date value as real date
###########################################################################
sub FixDate
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $date = $_[0];                           # save date arg

    my $day = 0;                                # init day of month
    my $mon = 0;                                # init month
    my $yr  = 0;                                # init year

    if ( $date eq '[yesterday]' )               # special "yesterday" date
    {
                                                # get cur date - 1 day (in secs)
        ($day, $mon, $yr) = (gmtime( time() - 86400 ))[3,4,5];
    }
    elsif ( $date eq '[today]' )                # special "today" date
    {
                                                # get current date
        ($day, $mon, $yr) = (gmtime( time() ))[3,4,5];
    }
    elsif ( $date eq '[tomorrow]' )             # special "tomorrow" date
    {
                                                # get cur date + 1 day (in secs)
        ($day, $mon, $yr) = (gmtime( time() + 86400 ))[3,4,5];
    }

    if ( $day )                                 # if date arg resolved
    {
        $mon++;                                 # fix month
        $yr += 1900;                            # fix year
                                                # reformat & glue it together
        #$date = sprintf( "%4d/%02d/%02d", $yr, $mon, $day );
        #$date = "$mon/$day/$yr";                # put it together
        $date = sprintf( "%d-%02d-%02d 00:00:00", $yr, $mon, $day );
        #$date = "$yr/$mon/$day";                # put it together
    }
    else                                        # date arg didn't resolve
    {
        $date = 0;                              # clear arg before rtn
    }

    return( $date );                            # rtn resolved date
}


###########################################################################
#   NAME: FixQueryCurUsr
#   DESC: fixes a resultset obj, rm'ing the def cq/xml usr & slamming in login
#   ARGS: query name, session obj, querydef obj, resultset obj, user's login
#   RTNS: err, resultset obj
###########################################################################
sub FixQueryCurUsr
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $query     = $_[0];                      # query name
    my $session   = $_[1];                      # session obj
    my $querydef  = $_[2];                      # querydef obj
    my $resultset = $_[3];                      # resultset obj
    my $login     = $_[4];                      # user's login

    my $curuser    = '';                        # current user
    my $sqlstr     = '';                        # SQL string of query
    my $qflddefs   = undef;                     # query field defs obj
    my $qflddefctr = 0;                         # query field def counter
    my $qflddefobj = undef;                     # query field def object
    my @fldlbls    = ();                        # field labels
    my $selstr     = '';                        # select string
    my $selcols    = '';                        # select columns
    my $selrest    = '';                        # rest of select
    my @selflds    = ();                        # select fields
    my $ordinalctr = 0;                         # 'T?.ordinal' counter

                                                # get current user's login
    eval{ $curuser = $session->GetUserLoginName() };
    return( "unable to determine user context for '$query'!" ) if ( $@ );
    if ( $curuser && $curuser ne $login )       # if cur user != login
    {
        eval{ $sqlstr = $querydef->GetSQL() };  # get SQL of query
        return( "unable to retrieve SQL for '$query'!" ) if ( $@ );
    }
    else                                        # cur user = login
    {
        return( '', $resultset );               # rtn resultset obj as is
    }

    if ( $sqlstr =~ s/'$curuser'/'$login'/g )   # if replace def usr w/ login
    {
        eval
        {
                                                # get query field defs obj
            $qflddefs = $querydef->GetQueryFieldDefs();
            $qflddefctr = $qflddefs->Count();   # get defs iterator
                                                # go thru query field defs
            for ( my $i=0; $i<$qflddefctr; $i++ )
            {
                                                # save off ea query field def
                $qflddefobj = $qflddefs->Item( $i );
                                                # get the field's label
                push( @fldlbls, $qflddefobj->GetLabel() ) if ( $qflddefobj->GetIsShown() );
            }
        };
        return( "unable to pull column labels from query '$query'!" ) if ( $@ );
                                                # if SELECT is parseable
        if ( $sqlstr =~ /^(select distinct )(.+)(\s+from\s+.*)$/ )
        {
            $selstr = $1; $selcols = $2; $selrest = $3;
            @selflds = split( /,/, $selcols );  # pull out rtn'd cols
                                                # any 'T#.ordinal's in there?
            $ordinalctr = grep( /^T\d+\.ordinal$/, @selflds );
                                                # if # cols = # labels
            if ( ($#selflds-$ordinalctr) == $#fldlbls )
            {
                $ordinalctr = 0;                # reset ordinal ctr for reuse
                                                # go thru cols
                for ( my $i=0; defined( $selflds[$i] ); $i++ )
                {
                                                # if ordinal select
                    if ( $selflds[$i] =~ /^T\d+\.ordinal$/ )
                    {
                                                # don't alias the ordinal
                        $selstr .= "$selflds[$i], ";
                        $ordinalctr++;          # inc ordinal ctr
                    }
                    else
                    {
                                                # add in column alias (cq label)
                        $selstr .= "$selflds[$i] AS '$fldlbls[$i-$ordinalctr]', ";
                    }
                }
                $selstr =~ s/, $/$selrest/;     # rm last comma
                $sqlstr = $selstr;              # save it off for good;
                                                # overwrite querydef's sql
                eval{ $querydef->SetSQL( $sqlstr ) };
                return( "unable to set SQL for '$login' query '$query'!" ) if ( $@ );
                                                # build new resultset obj
                eval{ $resultset = $session->BuildResultSet( $querydef ) };
                return( "unable to build query '$query'!" ) if ( $@ );
            }
            else                                # col & label counts don't match
            {
                return( "unable to determine column labels for query '$query'!" );
            }
        }
        else                                    # can't parse SELECT
        {
            return( "unable to extract columns from query '$query'!" );
        }
    }

    return( '', $resultset );                   # rtn no err & resultset obj
}


###########################################################################
#   NAME: QueryOutput
#   DESC: dumps the query output
#   ARGS: query name, resultset obj, (querydef obj)
#   RTNS: err, array of hashes of query rtn
###########################################################################
sub QueryOutput
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $query     = $_[0];                      # query name
    my $resultset = $_[1];                      # resultset obj
                                                # if querydef passed, use it
    my $querydef  = defined( $_[2] ) ? $_[2] : 0;

    my $qryerrstr = $query ? "query '$query'" : 'sql query';
    my $rectype   = '';                         # record type
    my $colctr    = 0;                          # column counter
    my $qstatus   = undef;                      # query move next status
    my @colprops  = ();
    my %queryrec  = ();                         # query rtn'd record tmp hash
    my $rowctr    = 0;                          # row counter
    my @rtn       = ();                         # init return array

    if ( $query )                               # if CQ query
    {
                                                # rec type rtn'd by query
        eval{ $rectype = lc( $resultset->LookupPrimaryEntityDefName() ) };
        return( "unable to determine record type for $qryerrstr!" ) if ( $@ );
    }
    else                                        # sql query
    {
        $rectype = 'record';                    # fake record type
    }

    eval{ $resultset->Execute() };              # execute query
    return( "unable to run $qryerrstr!" ) if ( $@ );
    eval                                        # protect us from all of this
    {
                                                # how many cols in output?
        $colctr = $resultset->GetNumberOfColumns();
        $qstatus = $resultset->MoveNext();      # go to 1st val
                                                # get col label & type
        @colprops = GetColProps( $query, $colctr, $resultset, $querydef );
                                                # while finding records
        while ( $qstatus == $CQPerlExt::CQ_SUCCESS )
        {
            %queryrec = ( row     => $rowctr++, # re-init w/ row counter
                          rectype => $rectype );
            for ( my $i=1; $i<=$colctr; $i++ )  # go thru record columns
            {
                                                # get column value
                $queryrec{${$colprops[$i]}{label}} = $resultset->GetColumnValue( $i );
                                                # if null multi-key ref-list fix
                $queryrec{${$colprops[$i]}{label}} = ''
                  if ( $querydef
                       && ${$colprops[$i]}{type} == $CQPerlExt::CQ_REFERENCE_LIST
                       && $queryrec{${$colprops[$i]}{label}} =~ /^\s+$/ );
            }
            push( @rtn, {%queryrec} );          # add record to return array
            $qstatus = $resultset->MoveNext();  # get next record
        }
    };
                                                # if something bad, throw err
    return( "invalid results from $qryerrstr!" ) if ( $@ );

    return( '', @rtn );                         # rtn err, query output
}


###########################################################################
#   NAME: GetColProps
#   DESC: column properties for the query
#   ARGS: query name, num of cols, resultset obj (already exec'd), querydef obj
#   RTNS: array of hashes [{label,type},]
###########################################################################
sub GetColProps
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $query     = $_[0];                      # query name
    my $colctr    = $_[1];                      # num of cols in query
    my $resultset = $_[2];                      # resultset obj (already exec'd)
    my $querydef  = $_[3];                      # querydef obj
    my @rtn       = ( 0 );                      # init rtn array (w/ val in [0])

    eval
    {
        for ( my $i=1; $i<=$colctr; $i++ )      # loop thru cols
        {
                                                # get col label
            $rtn[$i] = { label => $resultset->GetColumnLabel( $i ),
                         type  => $querydef     # if querydef passed
                                                #   get field type
                                  ? $querydef->GetFieldByPosition( $i )->GetFieldType()
                                  : 'sql',      #   just dump in 'sql'
                       };
                                                # if no label, make fake one
            ${$rtn[$i]}{label} = "column$i" if ( !$query && ! ${$rtn[$i]}{label} );
        }
    };
    return( @rtn );                             # rtn [{label,type},]
}


###########################################################################
#   NAME: GetQueryList
#   DESC: returns a list of queries for the current user
#   ARGS: session object, login, info hash
#   RTNS: error status, hash of arrays of query names
###########################################################################
sub GetQueryList
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session = shift( @_ );                  # session object
    my $login = shift( @_ );                    # user login
    my %info = @_;                              # save info hash
       $info{record} = defined( $info{record} ) ? lc( $info{record} ) : 'all';
       $info{dynamic} = defined( $info{dynamic} ) ? lc( $info{dynamic} ) : 'all';

    my $curuser   = '';                         # current user
    my $workspc   = undef;                      # workspace obj
    my $querydef  = undef;                      # querydef obj
    my @allqrys   = ();                         # all the user's queries
    my $rectype   = undef;                      # record type
    my $resultset = undef;                      # resultset obj
    my %badqrys   = ();                         # bad queries
    my $promptctr = 0;                          # prompt counter
    my $rowctr    = 0;                          # row counter
    my @rtn       = ();                         # init rtn array

    eval{ $workspc = $session->GetWorkSpace() }; # create workspace object
    return( "unable to create query workspace!" ) if ( $@ );
                                                # get current user's login
    eval{ $curuser = $session->GetUserLoginName() };
    if ( $curuser && $curuser ne $login )       # if cur user != login
    {
        eval{ $workspc->SetUserName( $login ) }; # force user's workspace
        return( "unable to set workspace for '$login'!" ) if ( $@ );
    }

    return( "invalid query type '$info{key}'!" )
      if ( !defined( $CqExt::wsqt{$info{key}} ) );
    eval{ @allqrys = sort( @{$workspc->GetQueryList( $CqExt::wsqt{$info{key}} )} ) };
    return( 'unable to retrieve query list!' ) if ( $@ );
    foreach $query ( @allqrys )                 # go thru list of queries
    {
        if ( $info{record} ne 'all' )           # if specific record type
        {
                                                # get query definition
            eval{ $querydef = $workspc->GetQueryDef( $query ) };
            return( "unable to retrieve definition for query '$query'!" ) if ( $@ );
                                                # rec type rtn'd by query
            eval{ $rectype = lc( $querydef->GetPrimaryEntityDefName() ) };
            return( "unable to determine record type for query '$query'!" ) if ( $@ );
                                                # skip if q rec type != req type
            next if ( $rectype ne $info{record} );
        }
        if ( $info{dynamic} ne 'all' )          # if not/prompted queries only
        {
                                                # get query definition
            eval{ $querydef = $workspc->GetQueryDef( $query ) };
            return( "unable to retrieve definition for query '$query'!" ) if ( $@ );
                                                # build the result set object
            eval{ $resultset = $session->BuildResultSet( $querydef ) };
            # prodd00477427 - <info...> with corrupted queries causes failure
            if ( $@ )                           # corrupted
            {
                $badqrys{$query} = [$@];        # save err msg
                next;                           # skip this query
            }
                                                # get number of prompts
            eval{ $promptctr = $resultset->GetNumberOfParams() };
            return( "unable to determine parameters for query '$query'!" ) if ( $@ );
                                                # skip if q dyn != req dyn
            next if ( ($info{dynamic} eq 'yes' && !$promptctr)
                      || ($info{dynamic} eq 'no' && $promptctr) );
        }

        %queryname = ( row     => $rowctr++,
                       rectype => 'queryname',
                       name    => $query ); # save query name
        push( @rtn, {%queryname} );         # add query name & stuff to rtn
    }

    MailBadQueries( $session, %badqrys ) if ( %badqrys );

    return( '', @rtn );                         # rtn err, query output
}


###########################################################################
#   NAME: MailBadQueries
#   DESC: formats a mail message about corrupted queries and sends to
#         CqSys::PrnBinMailMsg()
#   ARGS: session object, hash (query=>err)
#   RTNS: n/a
###########################################################################
sub MailBadQueries
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session = shift( @_ );                  # session obj
    my $login   = $session->GetUserLoginName(); # user's login
    my $email   = $session->GetUserEmail();     # user's email address
    my %badqrys = @_;                           # save bad queries
    my $msgbody = '';                           # init message body

    $msgbody .= "The CQ/XML Interface has detected the following corrupted queries in the 'Personal Queries' folder of '$login'.  These queries will not work with the CQ/XML Interface nor the ClearQuest Web interface.  Delete or edit these queries at your earliest convenience .\n\nFor information on maintaining queries, see the $CqSvr::tuttitle topic '$CqSvr::tuttopic' at:\n  $CqSvr::tuturl\n\nFor information on CQ/XML <info .../> elements, see the $CqSvr::xmltitle topic '$CqSvr::xmltopic' at:\n  $CqSvr::xmlurl\n\nIf you have questions about this error, submit a help request via the $CqSvr::helptitle at:\n  $CqSvr::helpurl\nPlease cut-and-paste this email into the request.\n\n*** CORRUPTED QUERIES ***\n\n";

    foreach $query ( sort( keys( %badqrys ) ) ) # 
    {
        $msgbody .= "  $query\n  ";
        $msgbody .= '-' x length( $query ) . "\n";
        foreach $errmsg ( @{$badqrys{$query}} )
        {
            $errmsg =~ s# at (\w:)?/.* line \d+\.\s*$##;
            $errmsg =~ s/\n/\n\t/g;
            $msgbody .= "\t$errmsg\n";
        }
        $msgbody .= "\n";
    }
    CqSys::PrnBinMailMsg( $msgbody, [$email], $CqSvr::qryerrsubj, 0, 0 );
}


###########################################################################
#   NAME: GetDbType
#   DESC: returns the db usage type for the current session
#   ARGS: session object
#   RTNS: error status, db type
###########################################################################
sub GetDbType
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session   = $_[0];                      # session object
    my $dbdescobj = undef;                      # databasedesc object
    my $dbname    = '';                         # db name
    my $dbsrvr    = '';                         # db server
                                                # mk dbdesc obj from cur ses db
    eval{ $dbdescobj = $session->GetSessionDatabase() };
    return( 'unable to retrieve the current database!' ) if ( $@ );
                                                # save db connect string
    eval{ $dbsrvr = $dbname = $dbdescobj->GetDatabaseConnectString() };
    return( 'unable to retrieve database connect string!' ) if ( $@ );
    $dbname =~ s/^.*DATABASE=([^;]+).*$/$1/og;  # parse out db & server names
    $dbsrvr =~ s/^.*(SERVER|Address)=([0-9A-Za-z-]+).*$/$2/og;

    if ( defined( $CqSvr::dbtypes{$dbsrvr} ) )  # if server mapping defined
    {
                                                # rtn db usage type
        return( '', "$dbname:$CqSvr::dbtypes{$dbsrvr}" );
    }
    else                                        # no server mapping defined?!?
    {
        return( 'unable to locate database in usage list!' ) if ( $@ );
    }
}


###########################################################################
#   NAME: TestLogin
#   DESC: tries to force a login as the requested session user
#   ARGS: db info hash
#   RTNS: error status, pass msg
###########################################################################
sub TestLogin
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my %dbinfo = %{$_[0]};                      # save db connect info
    my $tlsession = undef;                      # TestLogin session
    my $err = '';                               # init err str

                                                # try to login as user
    ($err, $tlsession) = Login( $dbinfo{login}, $dbinfo{password}, $dbinfo{db}, $dbinfo{repo}, 1, 1 );
    CQ::Logout( $tlsession );                   # logout the tmp session

    return( $err, "login as '$dbinfo{login}' successful" );                 # rtn err, success msg
}


###########################################################################
#   NAME: RawSql
#   DESC: runs raw sql against the db
#   ARGS: session obj, -content hash of sql elem
#   RTNS: error status, array of query vals [{fld=>val},]
###########################################################################
sub RawSql
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session = $_[0];                        # session obj
    my ($sql)   = each( %{$_[1]} );             # toss data struct & save sql

    my $resultset = undef;                      # query result set object
    my $err       = '';                         # init err rtn str
    my @rtn       = ();                         # init rtn array

                                                # define query via raw sql
    eval{ $resultset = $session->BuildSQLQuery( CqXml::FixXmlEnts( $sql, 1 ) ) };
    return( "unable to create sql query! ($@)" ) if ( $@ );
                                                # get query output & save
    ($err, @rtn) = QueryOutput( '', $resultset );
    return( $err ) if ( $err );

    return( $err, @rtn );                       # return query output
}


###########################################################################
#   NAME: SystemWait
#   DESC: puts the server in a wait state, where nothing is processed
#   ARGS: session obj
#   RTNS: error status
###########################################################################
sub SystemWait
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $session = $_[0];                        # session obj
    my $cqtan   = $_[1];                        # cq tan of cmd
    my $waitmsg = $_[2];                        # wait msg
    my @date    = (gmtime( time() ))[5,7];      # year & day of yr
                                                # yyddd
    my $datestr = sprintf( "%02d%03ds", $date[0]-100, $date[1] );
    my $sprusr  = undef;                        # super user?
    
                                                # is user super-user?
    eval{ $sprusr = $session->IsUserSuperUser() };
    return( "unable to determine user credentials! ($@)" ) if ( $@ );
    if ( !$sprusr )                             # if ! super user
    {
                                                # throw warning back
        eval { $sprusr = $session->GetUserLoginName() };
        return( "login '$sprusr' does not have permissions to issue the 'syswait' command!" );
    }
                                                # user is super, open wait file
    if ( open( SSD, ">$CqSvr::fulllogdir/$CqSvr::swfile$cqtan" ) )
    {
        print( SSD keys( %{$waitmsg} ) );       # prn passed message to file
        close( SSD );
        return( "message written to '$CqSvr::logdir/$CqSvr::swfile$cqtan'." );
    }
    else                                        # open failed
    {
        return( "unable to write syswait file!" );
    }
}


1;
