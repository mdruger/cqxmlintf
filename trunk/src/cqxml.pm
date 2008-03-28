###########################################################################
#   NAME: cqxml.pm
#   DESC: functions for parsing XML for the CQ  server
#   PKG:  CqXml
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
package CqXml;                                  # package name
require( 'cqext.pm' );                          # ClearQuest commands
require( 'cqsvrvars.pm' );                      # hard-coded file locations
require( 'cqsvrfuncs.pm' );                     # cq server functions
$debug = 0;                                     # init pkg'd debug var
my $errhdr = $main::errhdr ? $main::errhdr : 'ERROR:';


###########################################################################
#   NAME: PrelimXmlChk
#   DESC: checks that the input XML is well-formed
#   ARGS: scalar xml cmd
#   RTNS: err msg, reformatted xml cmd
###########################################################################
sub PrelimXmlChk
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $xml = $_[0];                            # save xml cmd for stripping
    my $xmlrtn = '';                            # xml to rtn & use
    my $err = '';                               # init err to ok rtn
                                                # standard error string
    my $stderrstr = "$errhdr unable to parse XML at";
    my $rtnerrstr = '';                         # return error string
    my @elems = ();                             # save all the start & end tags
    my @tree = ();                              # used to eval tree structure

    $xml =~ s/<!--((?:(?!-->)(.|\n))*)-->//og;  # rm comments (multi-line too)
                                                # fix empty elems to use end dec
    $xml =~ s/(<([^\s<>]+)[^<>]*)\/\s*>/$1><\/$2>/g;
                                                # fix CDATA w/ embedded XML
    $xml = FixXmlNCdata( $xml ) if ( $xml =~ /<!\[CDATA\[.*[<&].*\]\]>/os );
    $xmlrtn = $xml;                             # rtn massaged XML

                                                # out'a here if no <CQ..</CQ>
    return( "$errhdr unable to find '$CqSvr::rootelem' element!", $xmlrtn )
      if ( $xml !~ /<$CqSvr::rootelem.*<\/$CqSvr::rootelem>/s );
    $xml =~ s/\n//og;                           # remove <CR>
    $xml =~ s/<\?((?:(?!\?>).)*)\?>//og;        # remove declarations
                                                # remove CDATA
    $xml =~ s/<!\[CDATA\[((?:(?!\]\]>).)*)\]\]>//og;
                                                # remove proper entities
    $xml =~ s/(&lt;|&gt;|&amp;|&quot;|&apos;)//og;
    $xml =~ s/>[^<]*</></og;                    # remove (semi-)valid PCDATA
    $xml =~ s/ [^\s=&'"<>]+='[^']+'//og;        # remove single-quote attributes
    $xml =~ s/ [^\s=&'"<>]+="[^"]+"//og;        # remove dbl-quote attributes
    if ( $xml =~ /(\S+=[^<>]+)/ )               # if bad attributes
    {
                                                # prn err re bad attributes
        print( "$dbghdr attribute string = '$xml'!" ) if ( $debug );
        $rtnerrstr = "$stderrstr '$1'!";        # start building err rtn str
        $rtnerrstr = FixXmlEnts( $rtnerrstr );  # convert chars to XML entities
        return( $rtnerrstr, $xmlrtn );          # return err msg
    }

    #$xml =~ s/<[^<>\/\s]+\s*\/>//og;            # remove empty tags
    $xml =~ s/^\s*<(.+)>\s*$/$1/og;             # remove extra space
    if ( $xml =~ />([^<]+)</ )                  # if bad PCDATA
    {
        print( "$dbghdr PCDATA string = '$xml'!" ) if ( $debug );
        $rtnerrstr = "$stderrstr '$1'!";        # start building err rtn str
        $rtnerrstr = FixXmlEnts( $rtnerrstr );  # convert chars to XML entities
        return( $rtnerrstr );                   # return err msg
    }

    @elems = split( '><', $xml );               # split elem tags apart
    return( "$errhdr unable to find XML tags!", $xmlrtn ) if ( !@elems );
    for ( my $i=0; defined( $elems[$i] ); $i++ ) # go thru tags
    {
        $elems[$i] =~ s/^\s*(\S.*)$/$1/g;       # remove leading spaces
        $elems[$i] =~ s/^(.*\S)\s*$/$1/g;       # remove trailing spaces
        if ( $elems[$i] =~ m#^/(.+)$#  )        # if end tag
        {
            if ( $1 eq $tree[$#tree] )          # if end tag = last start tag
            {
                pop( @tree );                   # remove start tag from array
            }
            elsif ( $i <= 1 )                   # very 1st tag is munged
            {
                                                # return err re bad end tag
                return( "$stderrstr '&lt;$elems[$i]>'!", $xmlrtn );
            }
            else                                # end tag != last start tag
            {
                                                # return err re bad end tag
                return( "$stderrstr '&lt;$elems[$i-1]>'!", $xmlrtn );
            }
        }
        else                                    # assume start tag
        {
            push( @tree, $elems[$i] );          # add to tree array
        }
    }

    return( $err, $xmlrtn );                    # return err & new xml cmd
}


###########################################################################
#   NAME: FixXmlEnts
#   DESC: converts chars to XML entities or vice versa
#   ARGS: string to fix, (0=char->XML, 1=XML->char)
#   RTNS: fixed string
###########################################################################
sub FixXmlEnts
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $str = $_[0];                            # string to fix
    my $convmeth = defined( $_[1] ) ? $_[1] : 0; # conversion method

    if ( $convmeth )                            # XML->chars
    {
        $str =~ s/&gt;/>/og;                    # convert XML entities to
        $str =~ s/&lt;/</og;                    #  those "bad" characters
        $str =~ s/&quot;/"/og;
        $str =~ s/&apos;/'/og;
        $str =~ s/&amp;/&/og;                   # this one has to be done last
    }
    else                                        # chars->XML
    {
        $str =~ s/&/&amp;/og;                   # do this one 1st
        $str =~ s/</&lt;/og;
    }

    return( $str );                             # return the fixed string
}


###########################################################################
#   NAME: FixXmlNCdata
#   DESC: converts XML embedded in CDATA to entities
#   ARGS: XML to fix
#   RTNS: fixed XML
###########################################################################
sub FixXmlNCdata
{
    my $xml = $_[0];                            # save input
    $xml =~ s{^                                 # fix CDATA
                (                               # capture leading non-CDATA
                    (?:                         # RE grouping
                        (?!<!\[CDATA\[)         # find non-CDATA
                            .                   #   or anything
                    )*
                )
                (<!\[CDATA\[)                   # capture CDATA start
                (                               # capture CDATA
                    (?:                         # RE grouping
                        (?!\]\]>)               # find non-CDATA end
                        .                       #   or anything
                    )*
                )
                (\]\]>)                         # capture CDATA end
                (.*)                            # capture after the CDATA
            $}
             {                                  # now start replacing
                "$1$2" .                        # before CDATA & CDATA start
                FixXmlEnts( $3 ) .              # chg CDATA to entities
                "$4" .                          # add CDATA end
                FixXmlNCdata( $5 )              # recurse on the rest
             }xes;                              # comments, eval, ignore newline
    return( $xml );                             # return the fixed xml
}


###########################################################################
#   NAME: ReStructElems
#   DESC: saves records w/ desired 'wait' val & reorgs the XML::Mini hash
#   ARGS: wait val, client ip, XML::Mini->toHash() of CQ elem
#   RTNS: err status, array of record hashes
###########################################################################
sub ReStructElems
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $waitval = shift( @_ );                  # part of hash to rtn
    my $clientip = shift( @_ );                 # client ip
    my %xml = @_;                               # XML::Mini data structure
    my %dbinfo = GenDbInfo( $clientip, %xml );  # save db info (login/db/...)
    my $recerr = '';                            # record error
    my $err = '';                               # init err str var
    my @reclist = ();                           # record list
    my @rtn = ();                               # init return array

                                                # rtn err if no db info
    return( 'unable to resolve login information!' ) if ( !%dbinfo );

    foreach $rectype ( keys( %xml ) )           # go thru elements
    {
        if ( $rectype eq '!--' )                # if XML comment
        {
            next;                               # skip it
        }
                                                # if attribute
        elsif ( grep( /^$rectype$/, @CqSvr::cqatrbs ) )
        {
            next;                               # skip it
        }
                                                # just 1 record mod
        elsif ( ref( $xml{$rectype} ) eq 'HASH' )
        {
                                                # save record type into record
            ${$xml{$rectype}}{rectype} = $rectype;
                                                # save rec if "wait" ok
            ($recerr, @reclist) = SplitDataAtrb( ChkWaitVal( $waitval, $xml{$rectype} ) );
            push( @rtn, @reclist );             # push ok recs to rtn list
            $err .= $recerr if ( $recerr );     # save err if err
            $recerr = '';                       # re-init tmp err var
        }
                                                # >1 record mod
        elsif ( ref( $xml{$rectype} ) eq 'ARRAY' )
        {
                                                # go thru records
            foreach $record ( @{$xml{$rectype}} )
            {
                ${$record}{rectype} = $rectype; # save record type into record
                                                # save rec if "wait" ok
                ($recerr, @reclist) = SplitDataAtrb( ChkWaitVal( $waitval, $record ) );
                push( @rtn, @reclist );         # push ok recs to rtn list
                $err .= $recerr if ( $recerr ); # save err if err
                $recerr = '';                   # re-init tmp err var
            }
        }
                                                # record w/ no attributes
        elsif ( grep( /^$rectype$/, @CqSvr::recswoatrbs ) )
        {
                                                # nothing but PCDATA in there
            ($recerr, @reclist) = SplitDataAtrb( ChkWaitVal( $waitval, 
                { '-content' => $xml{$rectype}, 'rectype'  => $rectype } ) );
            push( @rtn, @reclist );             # push ok recs to rtn list
            $err .= $recerr if ( $recerr );     # save err if err
            $recerr = '';                       # re-init tmp err var
        }
        else                                    # unknown
        {
            #warn( "\a\aUnknown record type: '$rectype'!\n" );
            $err = "Unknown record type: '$rectype'!";
        }
    }

    unshift( @rtn, {%dbinfo} );                 # add db info to front of array
    return( $err, @rtn );                       # return array of record hashes
}


###########################################################################
#   NAME: GenDbInfo
#   DESC: creates a hash of db-connection info
#   ARGS: client ip, hash from XML::Mini
#   RTNS: hash of db-info on success, nothing on error
###########################################################################
sub GenDbInfo
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $cip = shift( @_ );                      # save off client ip
    my %db = @_;                                # save XML structure
    my %rtn = ();                               # init rtn hash
                                                # save all the db junk
    my $db    = defined( $db{db} ) ? $db{db} : $CqSvr::dbopts{db};
    my $repo  = defined( $db{repo} ) ? $db{repo} : $CqSvr::dbopts{repo};
    my $login = defined( $db{login} ) ? $db{login} : '';
    my $pswd  = defined( $db{password} )        # if password passed
                ? $db{password}                 # use passed password
                : defined( $db{encrypted} )     # if !pswd but encrypted passed
                                                # decrypt
                  ? CqSvr::Decrypt( $cip, $login, $db{encrypted} )
                  : '';                         # set to bad password val
                                                # failure email address
    my $emailfail = defined( $db{'email-fail'} ) ? $db{'email-fail'} : '';
                                                # now slam into hash
    %rtn = ( login=>$login, password=>$pswd, db=>$db, repo=>$repo, ip=>$cip, 'email-fail'=>$emailfail )
      if ( $login && $pswd );                   # if login & pswd resolved

    return( %rtn );                             # return db info hash
}


###########################################################################
#   NAME: ChkWaitVal
#   DESC: check "wait" val & rtn data if match
#   ARGS: wait val, record type, ref to record hash
#   RTNS: null if wait not match, XML-hash if wait match
###########################################################################
sub ChkWaitVal
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $wait = $_[0];                           # "wait" value
    my $chkthisrec = $_[1];                     # ref of xml rec hash

    if ( $wait eq $CqSvr::waitnondef            # if passed wait = non-default
         && defined( ${$chkthisrec}{wait} )     # and wait defined for this elem
         && ${$chkthisrec}{wait} eq $wait )     # and elem wait = passed wait
    {
        return( $chkthisrec );                  # return the xml rec hash
    }
    elsif ( $wait ne $CqSvr::waitnondef         # if passed wait != non-default
            && (!defined( ${$chkthisrec}{wait} ) # and wait !defined for elem
                                                #      or defined but != non-def
                || (${$chkthisrec}{wait} ne $CqSvr::waitnondef)) )
    {
        return( $chkthisrec );                  # return the xml rec hash
    }

    return( );                                  # no match, return empty
}


###########################################################################
#   NAME: SplitDataAtrb
#   DESC: splits the record P/CDATA from the attributes
#   ARGS: record hash
#   RTNS: err msg, array of fixed anon-hash records [{fld=>{val=>behav},},]
###########################################################################
sub SplitDataAtrb
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    return( '' ) if ( !defined( $_[0] ) );      # if nothing there, leave
    my %record = %{$_[0]};                      # save array of records
                                                # element attributes
    my @elematrb = qw( action wait rectype logic );
    my %okflds = ();                            # hash of ok fields
    my $uniqkey = '';                           # record unique key
    my $chkerr = '';                            # error per record
    my $rtnerr = '';                            # return error string
    my @rtnrecs = ();                           # return records

                                                # set def action if no action
    $record{action} = ${$CqSvr::recatrbdef{$record{rectype}}}{action}
      if ( !defined( $record{action} )
           && defined( ${$CqSvr::recatrbdef{$record{rectype}}}{action} ) );
                                                # pull unique key
    ($chkerr, $uniqkey) = GetRecUniqKey( %record );
    if ( $chkerr )                              # if error 
    {
                                                # append err to rtn str
        $rtnerr .= PrnErrXml( $record{rectype}, $record{action}, $uniqkey, $chkerr );
        return( $rtnerr, @rtnrecs );            # skip rest of this record
    }

    foreach $fld ( keys( %record ) )            # go thru record fields
    {
        if ( $fld eq '!--' )                    # if XML comment
        {
            next;                               # skip it
        }
                                                # if attribute
        elsif ( grep( /^$fld$/, @elematrb, @{$CqSvr::recatrbs{$record{rectype}}} ) )
        {
            next;                               # skip it
        }
                                                # uniq key
        elsif ( $fld eq $CqSvr::recuk{$record{rectype}} )
        {
                                                # trying to view/change uniq key
            if ( ref( $record{$fld} ) eq 'ARRAY' )
            {
                                                # pretend to pass the val
                ($chkerr, $okflds{$fld}) = GetFldInfo( $record{rectype}, '' );
            }
            else                                # don't want uniq key rtn'd
            {
                next;                           # skip it
            }
        }
        else                                    # standard record field
        {
                                                # get val & behavior
            ($chkerr, $okflds{$fld}) = GetFldInfo( $record{rectype}, $record{$fld} );
        }
        last if ( $chkerr );                    # stop proc rec if fld err
    }

    if ( $chkerr )                              # err fld parse, save err, !save
    {
        $rtnerr .= PrnErrXml( $record{rectype}, $record{action}, $uniqkey, $chkerr );
    }
    else                                        # field parse ok, save record
    {
                                                # save unique key
        ${$okflds{$CqSvr::atrbkey}}{key} = $uniqkey;
                                                # go thru atrbs & save back
        foreach $atrb ( @{$CqSvr::recatrbs{$record{rectype}}}, 'rectype' )
        {
            ${$okflds{$CqSvr::atrbkey}}{$atrb} = $record{$atrb} if ( defined( $record{$atrb} ) );
        }
        push( @rtnrecs, {%okflds} );            # save record to rtn array
    }

    return( $rtnerr, @rtnrecs );                # return err & saved records
}


###########################################################################
#   NAME: GetRecUniqKey
#   DESC: retrieves the record's unique key or an err msg
#   ARGS: record hash
#   RTNS: err msg, uniq key
###########################################################################
sub GetRecUniqKey
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested
    
    my %record = @_;                            # save record hash
    my $uniqkey = '';                           # init unique key var
    my $err = '';                               # 

                                                # non-supported record type
    if ( !defined( $CqSvr::recuk{$record{rectype}} ) )
    {
                                                # return err & bail out'a here
        return( "The '$record{rectype}' record type is not supported!" );
    }
                                                # no uniq key specified
    elsif ( !defined( $record{$CqSvr::recuk{$record{rectype}}} ) )
    {
                                                # if submit action
        if ( defined( $record{action} ) && $record{action} =~ /^submit$/i )
        {
            $uniqkey = '';                      # don't care about uk on submit
        }
                                                # record type w/o unique key
        elsif ( defined( $CqSvr::recuk{$record{rectype}} ) && !$CqSvr::recuk{$record{rectype}} )
        {
            $uniqkey = '';                      # don't return unique key
        }
        else                                    # non-submit action & no uniqkey
        {
                                                # return err & bail out'a here
            return( "Missing required $record{rectype} attribute '$CqSvr::recuk{$record{rectype}}'!" );
        }
    }
                                                # user wants uniq key back
    elsif ( ref( $record{$CqSvr::recuk{$record{rectype}}} ) eq 'ARRAY' )
    {
                                                # go thru uk vals & rtn req
        foreach $ukval ( @{$record{$CqSvr::recuk{$record{rectype}}}} )
        {
            if ( $ukval )                       # if actual val
            {
                                                # already have diff uniq key!?!
                if ( $uniqkey && $uniqkey ne $ukval )
                {
                    $err = "Multiple unique keys passed in $record{rectype} request!";
                    $uniqkey .= "/$ukval";
                }
                else                            # 1st time for this uniq key
                {
                    $uniqkey = $ukval;          # save unique key
                }
            }
        }
    }
    else                                        # action ok, uniq key ok
    {
                                                # save uniq key in nice var
        $uniqkey = $record{$CqSvr::recuk{$record{rectype}}};
    }

    return( $err, $uniqkey );                     # rtn no err msg & uniqkey
}


###########################################################################
#   NAME: GetFldInfo
#   DESC: reorgs field info into anon-hash
#   ARGS: record type, field data struct as returned from XML::Mini
#   RTNS: err msg, field info {fld=>val=>behavior}
###########################################################################
sub GetFldInfo
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $rectype = $_[0];                        # 
    my $fldval = $_[1];                         # save field data
    my $cpcdata = '';                           # init P/CDATA tmp var
    my $multierr = '';                          # recursion err
    my $multirtn = '';                          # recursion rtn data struct
    my @multihash = ();                         # array 2 pull anon-hash pair
    my %rtn = ();                               # return hash
    my $err = '';                               # err message

    if ( ref( $fldval ) eq 'HASH' )             # extra atrb or CDATA
    {
        if ( defined( ${$fldval}{'-content'} ) ) # PCDATA
        {
            $cpcdata = ${$fldval}{'-content'};  # save PCDATA as value
        }
        elsif ( defined( ${$fldval}{CDATA} ) )  # CDATA
        {
            $cpcdata = ${$fldval}{CDATA};       # save CDATA as value
        }
        else                                    # no PCDATA, no CDATA
        {
            return( 'Unable to parse attributes!' );
        }

        $cpcdata = FixXmlEnts( $cpcdata, 1 );   # convert XML ents -> chars

                                                # go thru rec type attributes
        foreach $atrb ( keys( %{$CqSvr::fldatrbs{$rectype}} ) )
        {
                                                # if attribute defined, save it
            $rtn{"$cpcdata"} = ${$fldval}{$atrb} if ( defined( ${$fldval}{$atrb} ) );
        }

        if ( !defined( $rtn{"$cpcdata"} ) )     # recs w/o defined attribs
        {
                                                # go thru rec attribs
            foreach $key ( keys( %{$CqSvr::fldatrbs{$rectype}} ) )
            {
                                                # save default attrib val
                $rtn{$cpcdata} = ${$CqSvr::fldatrbs{$rectype}}{$key};
            }
        }
    }
    elsif ( ref( $fldval ) eq 'ARRAY' )         # glob of field values
    {
        foreach $multival ( @{$fldval} )        # go thru ea field value
        {
                                                # break ea field val into struct
            ($multierr, $multirtn) = GetFldInfo( $rectype, $multival );
                                                # just return err if problem
            return( $multierr ) if ( $multierr );
            @multihash = %{$multirtn};          # save key/val into array
            $rtn{$multihash[0]} = $multihash[1]; # use anon key/val to rtn hash
        }
    }
                                                # std rec types w/o attribs
    elsif ( grep( /^$rectype$/, @CqSvr::recswoatrbs ) )
    {
        $fldval = FixXmlEnts( $fldval, 1 );     # convert XML ents -> chars
        $rtn{"$fldval"} = $rectype;             # hack! save PCDATA as fld val
    }
    else                                        # plain PCDATA
    {
        $fldval = FixXmlEnts( $fldval, 1 );     # convert XML ents -> chars

                                                # go thru rec type attributes
        foreach $atrb ( keys( %{$CqSvr::fldatrbs{$rectype}} ) )
        {
                                                # plain 'o val w/ def atrb
            $rtn{"$fldval"} = ${$CqSvr::fldatrbs{$rectype}}{$atrb};
        }
    }

    return( $err, {%rtn} );                     # return err & {fld=>val}
}


###########################################################################
#   NAME: CqExecXml
#   DESC: exec's ClearQuest commands
#   ARGS: cqtan, rtn array from ProcessXml()
#   RTNS: status wrapped in XML, errors
###########################################################################
sub CqExecXml
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $cqtan = shift( @_ );                    # transaction number
    my $dbinfo = shift( @_ );                   # db info
    my @xml = @_;                               # array of record hashes
    my %record = ();                            # tmp record hash
    my %recatrb = ();                           # tmp hash of record attributes
    my %cqrtn = ();                             # cq return vals
    my @arrayrtn = ();                          # rtn var for junk in arrays
    my $cqerr = '';                             # cq err rtn
    my $tmpstr = '';                            # tmp str
    my $rtn = '';                               # xml status rtn str
    my $errctr = 0;                             # errors rtn ctr
    my $session = undef;                        # cq session

                                                # create cq session
    ($cqerr, $session) = CQ::Login( ${$dbinfo}{login}, ${$dbinfo}{password}, ${$dbinfo}{db}, ${$dbinfo}{repo}, $cqtan );
    foreach $recref ( @xml )                    # go thru records
    {
        %cqrtn = ();                            # re-init cq return hash
        %record = %{$recref};                   # save ref to tmp hash
        %recatrb = %{$record{$CqSvr::atrbkey}}; # save atrbs to tmp hash
        delete( $record{$CqSvr::atrbkey} );     # rm 'atrb' key/val & continue

        if ( $cqerr )                           # session/login failure
        {
            $cqerr = FixXmlEnts( $cqerr );      # convert chars to XML entities
                                                # gen err msg
            $rtn .= PrnErrXml( $recatrb{rectype}, $recatrb{action}, $recatrb{key}, $cqerr );
            $errctr++;                          # inc err ctr
            next;                               # done with this one
        }

        if ( $recatrb{rectype} eq 'query' )     # if query element
        {
                                                # call our massive query func
            ($cqerr, @arrayrtn) = CQ::Query( $session, ${$dbinfo}{login}, $recatrb{key}, %record );
        }
        elsif ( $recatrb{rectype} eq 'info' )   # if info element
        {
                                                # if query listing
            if ( $recatrb{key}    eq 'Personal Queries'
                 || $recatrb{key} eq 'Public Queries'
                 || $recatrb{key} eq 'All Queries' )
            {
                                                # go get query list
                ($cqerr, @arrayrtn) = CQ::GetQueryList( $session, ${$dbinfo}{login}, %recatrb );
            }
            elsif ( $recatrb{key} eq 'dbtype' ) # production or not?
            {
                ($cqerr, @arrayrtn) = CQ::GetDbType( $session );
            }
            elsif ( $recatrb{key} eq 'login' )  # login okay?
            {
                ($cqerr, @arrayrtn) = CQ::TestLogin( $dbinfo );
            }
            elsif ( $recatrb{key} eq 'syswait' )
            {
                ($cqerr) = CQ::SystemWait( $session, $cqtan, $record{'-content'} );
            }
            else                                # what the hell?
            {
                $cqerr = "unknown $recatrb{rectype} type '$recatrb{key}'!";
            }
        }
        elsif ( $recatrb{rectype} eq 'sql' )    # if sql element
        {
            ($cqerr, @arrayrtn) = CQ::RawSql( $session, $record{'-content'} );
        }
        elsif ( $recatrb{action} =~ /^view$/i ) # view the record
        {
            if ( !%record )                     # no fields, dump entire record
            {
                ($cqerr, %cqrtn) = CQ::Dump( $session, $recatrb{rectype}, $recatrb{key} );
            }
            else                                # view specific fields
            {
                ($cqerr, %cqrtn) = CQ::View( $session, $recatrb{rectype}, $recatrb{key}, keys( %record ) );
            }
        }
                                                # if submit action
        elsif ( $recatrb{action} =~ /^submit$/i )
        {
            ($cqerr, $cqrtn{$CqSvr::recuk{$recatrb{rectype}}}) = CQ::Submit( $session, $recatrb{rectype}, %record );
        }
                                                # delete a record?!?
        elsif ( $recatrb{action} =~ /^delete$/i )
        {
            $cqerr = CQ::Delete( $session, $recatrb{rectype}, $recatrb{key} );
        }
        else                                    # some other action
        {
            if ( !%CqSvr::modperms )            # permissions disabled
            {
                $cqerr = CQ::Action( {}, $session, $recatrb{rectype}, $recatrb{key}, $recatrb{action}, %record );
            }
                                                # if ip has permissions
            elsif ( defined( %{$CqSvr::modperms{${$dbinfo}{ip}}} ) )
            {
                $cqerr = CQ::Action( \%{$CqSvr::modperms{${$dbinfo}{ip}}}, $session, $recatrb{rectype}, $recatrb{key}, $recatrb{action}, %record );
            }
                                                # if login has permissions
            elsif ( defined( %{$CqSvr::modperms{${$dbinfo}{login}}} ) )
            {
                $cqerr = CQ::Action( \%{$CqSvr::modperms{${$dbinfo}{login}}}, $session, $recatrb{rectype}, $recatrb{key}, $recatrb{action}, %record );
            }
            else                                # no permissions
            {
                                                # fake ip/login perm chk
                $cqerr = CQ::Action( {'nomatch'=>'nomatch'}, $session, $recatrb{rectype}, $recatrb{key}, $recatrb{action}, %record );
            }
        }

        if ( $cqerr )                           # err rtn'd
        {
            $cqerr = FixXmlEnts( $cqerr );      # convert chars to XML entities
            $rtn .= PrnErrXml( $recatrb{rectype}, $recatrb{action}, $recatrb{key}, $cqerr );
            $cqerr = '';                        # re-init tmp err var
            $errctr++;                          # inc err ctr
        }
        elsif ( $recatrb{rectype} eq 'query' || $recatrb{rectype} eq 'sql' )  # no err rtn'd
        {
            $rtn .= "$CqSvr::rtnleadspc<$recatrb{rectype}";
            $rtn .= " $CqSvr::recuk{$recatrb{rectype}}='$recatrb{key}'" if ( $CqSvr::recuk{$recatrb{rectype}} );
            $rtn .= " status='ok'>\n";
            foreach $queryrec ( @arrayrtn )     # go thru rtn'd rows
            {
                $rtn .= "$CqSvr::rtnleadspc"x2;
                $rtn .= "<${$queryrec}{rectype} $CqSvr::queryatrb{counter}='${$queryrec}{$CqSvr::queryatrb{counter}}'>\n";
                foreach $field ( keys( %{$queryrec} ) )
                {
                                                # skip if elem or atrb
                    next if ( grep( /^$field$/, (values( %CqSvr::queryatrb ), 'dbid') ) );
                    $rtn .= "$CqSvr::rtnleadspc"x3;
                    #$rtn .= "<$field>${$queryrec}{$field}</$field>\n";
                                                # save rtn'd field to tmp var
                    $tmpstr = ${$queryrec}{$field};
                                                # convert chars to XML entities
                    $tmpstr = FixXmlEnts( $tmpstr );
                    $rtn .= "<$field>$tmpstr</$field>\n";
                }
                $rtn .= "$CqSvr::rtnleadspc"x2;
                $rtn .= "</${$queryrec}{rectype}>\n";
            }
            $rtn .= "$CqSvr::rtnleadspc</$recatrb{rectype}>\n";
        }
        elsif ( $recatrb{rectype} eq 'info' )   # no err, info "record"
        {
            if ( $recatrb{key}    eq 'Personal Queries'
                 || $recatrb{key} eq 'Public Queries'
                 || $recatrb{key} eq 'All Queries' )
            {
                $rtn .= "$CqSvr::rtnleadspc<$recatrb{rectype} $CqSvr::recuk{$recatrb{rectype}}='$recatrb{key}' status='ok'>\n";
                foreach $inforec ( @arrayrtn )  # go thru rtn'd rows
                {
                    $rtn .= "$CqSvr::rtnleadspc"x2;
                    $rtn .= "<${$inforec}{rectype} $CqSvr::queryatrb{counter}='${$inforec}{$CqSvr::queryatrb{counter}}'>";
                    $tmpstr = ${$inforec}{name}; # save query name
                                                # convert chars to XML entities
                    $tmpstr = FixXmlEnts( $tmpstr );
                    $rtn .= "$tmpstr</${$inforec}{rectype}>\n";
                }
                $rtn .= "$CqSvr::rtnleadspc</$recatrb{rectype}>\n";
            }
            else                                # dbtype, login
            {
                                                # write element start
                $rtn .= "$CqSvr::rtnleadspc<$recatrb{rectype} $CqSvr::recuk{$recatrb{rectype}}='$recatrb{key}' status='ok'>\n";
                foreach $dbtype ( @arrayrtn )   # go thru rtn'd values
                {
                    $rtn .= "$CqSvr::rtnleadspc"x2;
                                                # write test value
                    $rtn .= "<$recatrb{key}>$dbtype</$recatrb{key}>\n";
                }
                                                # write element end
                $rtn .= "$CqSvr::rtnleadspc</$recatrb{rectype}>\n";
            }
        }
        else                                    # no err rtn'd
        {
                                                # prn "ok" line: rec/key/act/ok
            $rtn .= "$CqSvr::rtnleadspc<$recatrb{rectype} ";
            $rtn .= "$CqSvr::recuk{$recatrb{rectype}}='$recatrb{key}' "
              if ( defined( $recatrb{key} ) && defined( $CqSvr::recuk{$recatrb{rectype}} ) );
            $rtn .= "action='$recatrb{action}' " if ( defined( $recatrb{action} ) );
            $rtn .= "status='ok'";
            if ( %cqrtn )                       # if sub-elements
            {
                $rtn .= ">\n";                  # finish this element tag
                                                # go thru rtn'd fields
                foreach $recfld ( sort( keys( %cqrtn ) ) )
                {
                                                # prn field label & val
                    $rtn .= "$CqSvr::rtnleadspc"x2;
                    #$rtn .= "<$recfld>$cqrtn{$recfld}</$recfld>\n";
                    $tmpstr = $cqrtn{$recfld};  # save rtn'd field to tmp var
                                                # convert chars to XML entities
                    $tmpstr = FixXmlEnts( $tmpstr );
                    $rtn .= "<$recfld>$tmpstr</$recfld>\n";
                }
                                                # end record elem
                $rtn .= "$CqSvr::rtnleadspc</$recatrb{rectype}>\n";
            }
            else                                # no sub-elements
            {
                $rtn .= "/>\n";                 # finish empty element
            }
        }
    }

    CQ::Logout( $session );                     # done so logout

    return( $rtn, $errctr );                    # return status str & err ctr
}


###########################################################################
#   NAME: PrnErrXml
#   DESC: creates an XML error message
#   ARGS: record type, action, unique key, error message
#   RTNS: XML string
###########################################################################
sub PrnErrXml
{
    CqSvr::PrnDbgHdr( @_ ) if ( $debug );       # print debug info if requested

    my $rectype = $_[0];                        # record type
    my $action  = $_[1];                        # action
    my $uniqkey = $_[2];                        # unique key
    my $cqerr   = $_[3];                        # error message
    my $rtnstr  = '';                           # return string

    $rtnstr = "$CqSvr::rtnleadspc<$rectype ";   # space + element start
                                                # add unique key if passed
    $rtnstr .= "$CqSvr::recuk{$rectype}='$uniqkey' " if ( $uniqkey );
                                                # add action for records
    $rtnstr .= "action='$action' " unless ( grep( /^$rectype$/, @CqSvr::recswoactions ) );
                                                # finish of the xml
    $rtnstr .= "status='error'>$cqerr</$rectype>\n";

    return( $rtnstr );                          # return xml string
}


1;
