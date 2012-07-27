#!/usr/bin/perl
use Modern::Perl;
use C4::Context;
use C4::AuthoritiesMarc;
use C4::Biblio;
use C4::Search;
use C4::Charset;
use C4::Debug;
use C4::ZebraIndex;

use Getopt::Long;
use YAML;
use List::MoreUtils qw/uniq/;

my @matchstrings;
my $choosemethod = "u";   # by default, choose to keep the most used authority
my ($verbose, $all, $help, $wherestring, $test);

# default is to check all these subfields for 'auth_tag_to_report'
my $check = 'TAGabcdefghitxyz';

my $result = GetOptions (
    "match=s"   => \@matchstrings
    , "verbose+"  => \$verbose
    , "all|a"  => \$all
    , "test|t"  => \$test
    , "help|h"   => \$help
    , "where=s"   => \$wherestring
    , "choose-method=s" => \$choosemethod
    , "check=s" => \$check
);

if ( $help || ! (@ARGV || $all)) {
    print_usage();
    exit 0;
}

my @choose_subs;
foreach (split //, $choosemethod) {
    given($_) {
        when ('d') {
            push @choose_subs, \&_get_date;
        }
        when ('p') {
            push @choose_subs, \&_has_ppn;
        }
        when ('u') {
            push @choose_subs, \&_get_usage;
        }
        default {
            warn "Choose method '$_' is not supported";
        }
    }
}

my @checks;
foreach my $c (split /,/, $check) {
    my $field = substr $c, 0, 3;
    my $subfields = substr $c, 3;
    if ($field =~ /^[0-9][0-9.]{2}$/ or $field eq "TAG") {
        my @subf = grep /^[0-9a-z]$/, uniq split //, $subfields;
        if (@subf == 0 and not MARC::Field->is_controlfield_tag($field)) {
            die "Field '$field' is not a control field and no subfields are given";
        }
        if (@subf > 0 and MARC::Field->is_controlfield_tag($field)) {
            die "Field '$field' is a control field but you have given subfields";
        }
        push @checks, {
            field => $field,
            subfields => \@subf
        };
    } else {
        die "'$field' is not a valid tag";
    }
}

my $dbh = C4::Context->dbh;

$verbose and logger("Fetching authtypecodes...");
my $authtypes_ref = $dbh->selectcol_arrayref(
    qq{SELECT authtypecode, auth_tag_to_report FROM auth_types},
    { Columns=>[1,2] }
);
my %authtypes=@$authtypes_ref;
$verbose and logger("Fetching authtypecodes done.");

my %biblios;
my %authorities;
my @authtypecodes = @ARGV ;
@authtypecodes = keys %authtypes unless(@authtypecodes);

unless (@matchstrings) {
    @matchstrings = ('at/152b##he/2..abxyz');
}

$verbose and logger("Preparing matchstrings...");
my @attempts = prepare_matchstrings(@matchstrings);
$verbose and logger("Preparing matchstrings done.");

for my $authtypecode (@authtypecodes) {
    $verbose and logger("Deduping authtype '$authtypecode'");
    $verbose and logger("Fetching all authids for '$authtypecode'... ");
    my @sqlparams;
    my $strselect
        = qq{SELECT authid, NULL FROM auth_header where authtypecode=?};
    push @sqlparams, $authtypecode;
    if ($wherestring) {
        $strselect .= " and $wherestring";
    }
    my $auth_ref
        = $dbh->selectcol_arrayref( $strselect, { Columns => [ 1, 2 ] },
        @sqlparams );
    $verbose and logger("Fetching authids done.");
    my $auth_tag = $authtypes{$authtypecode};
    my %hash_authorities_authtypecode;
    if ($auth_ref){
        %hash_authorities_authtypecode=@$auth_ref;
        $verbose and logger("Building authorities hash...");
        @authorities{keys %hash_authorities_authtypecode} = values %hash_authorities_authtypecode;
        $verbose and logger("Building authorities hash done.");
    }
    $verbose and logger("Start deduping for authtype '$authtypecode'");
    my $size = scalar keys %hash_authorities_authtypecode;
    my $i = 1;
    for my $authid ( keys %hash_authorities_authtypecode ) {
        if ($verbose >= 2) {
            my $percentage = sprintf("%.2f", $i * 100 / $size);
            logger("Processing authority $authid ($i/$size $percentage%)");
        } elsif ($verbose and ($i % 100) == 0) {
            my $percentage = sprintf("%.2f", $i * 100 / $size);
            logger("Progression for authtype '$authtypecode': $i/$size ($percentage%)");
        }

        #authority was marked as duplicate
        next if $authorities{$authid};
        my $authrecord = GetAuthority($authid);

        # next if cannot take authority
        next unless $authrecord;
        SetUTF8Flag($authrecord);
        my $success;
        for my $attempt (@attempts) {
            ($verbose >= 2) and logger("Building query...");
            my $query = _build_query( $authrecord, $attempt );
            ($verbose >= 2) and logger("Building query done.");
            $debug and $query and warn $query;
            # This prevent too general queries to be executed
            # TODO: This should allow more than these 3 indexes
            next unless $query =~ /(he|he-main|ident)(,\S*)*(=|:)/;

            ($verbose >= 2) and logger("Searching...");
            my ($error, $results) = SimpleSearch($query, undef, undef, ["authorityserver"]);
            if ( $error || !$results ) {
                $debug and warn $@;
                $debug and warn $error;
                $debug and warn YAML::Dump($query);
                $debug and warn $auth_tag;
                next;
            }
            $debug and warn YAML::Dump($results);
            next if ( !$results or scalar( @$results ) < 1 );
            my @recordids = map {
                _get_id( MARC::Record->new_from_usmarc($_) )
            } @$results;
            ($verbose >= 2) and logger("Searching done.");

            ($verbose >= 2) and logger("Choosing records...");
            my ( $recordid_to_keep, @recordids_to_merge )
                = _choose_records( $authid, @recordids );
            ($verbose >= 2) and logger("Choosing records done.");
            unless ($test or @recordids_to_merge == 0) {
                ($verbose >= 2) and logger("Merging ". join(',',@recordids_to_merge) ." into $recordid_to_keep.");
                for my $localauthid (@recordids_to_merge) {
                    my @editedbiblios = eval {
                        merge( $localauthid, undef, $recordid_to_keep, undef )
                    };
                    if ($@) {
                        warn "merging $localauthid into $recordid_to_keep failed :", $@;
                    } else {
                        for my $biblio (@editedbiblios){
                            $biblios{$biblio} = 1;
                        }
                        $authorities{$localauthid} = 2;
                    }
                }
                ($verbose >= 2) and logger("Merge done.");
                $authorities{$recordid_to_keep} = 1;
            } elsif ($verbose >= 2) {
                if (@recordids_to_merge > 0) {
                    logger('Would merge '
                        . join(',', @recordids_to_merge)
                        . " into $recordid_to_keep.");
                } else {
                    logger("No duplicates found for $recordid_to_keep");
                }
            }
        }
        $i++;
    }
    $verbose and logger("End of deduping for authtype '$authtypecode'");
}

# Update biblios
my @biblios_to_update = grep {defined $biblios{$_} and $biblios{$_} == 1}
                            keys %biblios;
if( @biblios_to_update > 0 ) {
    logger("Updating biblios index (" . scalar(@biblios_to_update) . " biblios to update)");
    C4::ZebraIndex::IndexRecord("biblio", \@biblios_to_update,
        { as_xml => 1, record_format => "marcxml" });
} else {
    logger("No biblios to update");
}

# Update authorities
my @authorities_to_update = grep{defined $authorities{$_} and $authorities{$_} == 1}
                                keys %authorities;
if( @authorities_to_update > 0 ) {
    logger("Updating authorities index (" . scalar(@authorities_to_update) . " authorities to update)");
    C4::ZebraIndex::IndexRecord("authority", \@authorities_to_update,
        { as_xml => 1, record_format => "marcxml" });
} else {
    logger("No autorities to update");
}

# Delete authorities
my @authorities_to_delete = grep{defined $authorities{$_} and $authorities{$_} == 2}
                                keys %authorities;
if( @authorities_to_delete > 0 ) {
    logger("Deleting authorities from index (" . scalar(@authorities_to_delete) . " authorities to delete)");
    C4::ZebraIndex::DeleteRecordIndex("authority", \@authorities_to_delete,
        { as_xml => 1, record_format => "marcxml" });
} else {
    logger("No authorities to delete");
}

exit 0;

sub compare_arrays{
    my ($arrayref1,$arrayref2)=@_;
    return 0 if scalar(@$arrayref1)!=scalar(@$arrayref2);
    my $compare=1;
    for (my $i=0;$i<scalar(@$arrayref1);$i++){
        $compare = ($compare and ($arrayref1->[$i] eq $arrayref2->[$i]));
    }
    return $compare;
}

sub prepare_matchstrings {
    my @structure;
    for my $matchstring (@_) {
        my @andstrings      = split /##/,$matchstring;
        my @matchelements = map {
            my $hash;
            @$hash{qw(index subfieldtag)} = split '/', $_;
            if ($$hash{subfieldtag}=~m/([0-9\.]{3})(.*)/) {
                @$hash{qw(tag subfields)}=($1,[ split (//, $2) ]);
            }
            delete $$hash{subfieldtag};
            $hash
        } @andstrings;
        push @structure , \@matchelements;
    }
    return @structure;
}

#trims the spaces before and after a string
#and normalize the number of spaces inside
sub trim{
    map{
       my $value=$_;
       $value=~s/\s+$//g;
       $value=~s/^\s+//g;
       $value=~s/\s+/ /g;
       $value;
    }@_
}

sub prepare_strings{
    my $authrecord=shift;
    my $attempt=shift;
    my @stringstosearch;
    for my $field ($authrecord->field($attempt->{tag})){
        if ($attempt->{tag} le '009'){
            if ($field->data()){
                push @stringstosearch, trim($field->data());
            }
        }
        else {
            if ($attempt->{subfields}){
                for my $subfield (@{$attempt->{subfields}}){
                    push @stringstosearch, trim(map { NormalizeString($_, undef, 1) } $field->subfield($subfield));
                }
            }
            else {
                push @stringstosearch,  trim(map { NormalizeString($_, undef, 1) } $field->as_string());
            }

        }
    }
    return map {
                ( $_
                ?  qq<$$attempt{'index'}=\"$_\">
                : () )
            }@stringstosearch;
}

sub _build_query{
    my $authrecord = shift;
    my $attempt = shift;
    if ($attempt) {
        my $query = join ' AND ', map {
            prepare_strings($authrecord, $_)
        } @$attempt;
        return $query;
    }
    return;
}

sub _get_id {
    my $record = shift;

    if($record and (my $field = $record->field('001'))) {
        return $field->data();
    }
    return 0;
}

sub _has_ppn {
    my $record = shift;

    if($record and (my $field = $record->field('009'))) {
        return $field->data() ? 1 : 0;
    }
    return 0;
}

sub _get_date {
    my $record = shift;

    if($record and (my $field = $record->field('005'))) {
        return $field->data();
    }
    return 0;
}

sub _get_usage {
    my $record = shift;

    if($record and (my $field = $record->field('001'))) {
        return CountUsage($field->data());
    }
    return 0;
}

=head2 _choose_records
    this function takes input of candidate record ids to merging
    and returns
        first the record to merge to
        and list of records to merge from
=cut
sub _choose_records {
    my @recordids = @_;

    my @records = map { GetAuthority($_) } @recordids;
    my @candidate_auths =
      grep { _is_duplicate( $recordids[0], $records[0], _get_id($_), $_ ) }
      ( @records[ 1 .. $#records ] );

    # See http://www.sysarch.com/Perl/sort_paper.html Schwartzian transform
    my @candidate_authids =
        map $_->[0] =>
        sort {
            $b->[1] <=> $a->[1] ||
            $b->[2] <=> $a->[2] ||
            $b->[3] <=> $a->[3]
        }
        map [
            _get_id($_),
            $choose_subs[0] ? $choose_subs[0]->($_) : 0,
            $choose_subs[1] ? $choose_subs[1]->($_) : 0,
            $choose_subs[2] ? $choose_subs[2]->($_) : 0
        ] =>
        ( $records[0], @candidate_auths );

    return @candidate_authids;
}

sub compare_subfields {
    my ($field1, $field2, $subfields) = @_;

    my $certainty = 1;
    foreach my $subfield (@$subfields) {
        $debug && warn "Comparing ". $field1->tag() ."\$$subfield ",
            "to ". $field2->tag(). "\$$subfield";

        my @subfields1 = $field1->subfield($subfield);
        my @subfields2 = $field2->subfield($subfield);

        if (compare_arrays([ trim(@subfields1) ], [ trim(@subfields2) ])) {
            $debug && warn "certainty 1 ", @subfields1, " ", @subfields2;
        } else {
            $debug && warn "certainty 0 ", @subfields1, " ", @subfields2;
            $certainty = 0;
            last;
        }
    }

    return $certainty;
}

sub _is_duplicate {
    my ( $authid1, $authrecord, $authid2, $marc ) = @_;
    return 0 if ( $authid1 == $authid2 );
    $authrecord ||= GetAuthority($authid1);
    $marc       ||= GetAuthority($authid2);
    if (!$authrecord){
        warn "no or bad record for $authid1";
        return 0;
    }
    if (!$marc){
        warn "no or bad record for $authid2";
        return 0;
    }
    my $at1        = GetAuthTypeCode($authid1);
    if (!$at1){
        warn "no or bad authoritytypecode for $authid1";
        return 0;
    }
    my $auth_tag   = $authtypes{$at1} if (exists $authtypes{$at1});
    my $at2        = GetAuthTypeCode($authid2);
    if (!$at2){
        warn "no or bad authoritytypecode for $authid2";
        return 0;
    }
    my $auth_tag2  = $authtypes{$at2} if (exists $authtypes{$at2});
    $debug and warn YAML::Dump($authrecord);
    $debug and warn YAML::Dump($marc);
    SetUTF8Flag($authrecord);
    SetUTF8Flag($marc);
    my $certainty = 1;

    $debug and warn "_is_duplicate ($authid1, $authid2)";
    if ( $marc->field($auth_tag2)
        and !( $authrecord->field($auth_tag) ) )
    {
        $debug && warn "certainty 0 ";
        return 0;
    }
    elsif ( $authrecord->field($auth_tag)
        && !( $marc->field($auth_tag2) ) )
    {
        $debug && warn "certainty 0 ";
        return 0;
    }

    foreach my $check (@checks) {
        last if ($certainty == 0);
        my $field = $check->{field};
        my $subfields = $check->{subfields};
        my ($tag1, $tag2) = ($field, $field);
        if ($field eq "TAG") {
            $tag1 = $auth_tag;
            $tag2 = $auth_tag2;
        }

        my @fields1 = $marc->field($tag1);
        my @fields2 = $authrecord->field($tag2);
        if (scalar @fields1 != scalar @fields2) {
            $debug && warn "Not the same number of fields: ",
                "id $authid1: ". scalar @fields1 ." fields '$tag1', ",
                "id $authid2: ". scalar @fields2 ." fields '$tag2'.";
            $certainty = 0;
            last;
        }

        for (my $i=0; $i<@fields1; $i++) {
            if (@$subfields > 0) {
                $certainty = compare_subfields($fields1[$i], $fields2[$i], $subfields);
                last if ($certainty == 0);
            } else {
                $debug && warn "Comparing ".$fields1[$i]->tag()." data ",
                    "to ".$fields2[$i]->tag()." data";
                if ($fields1[$i]->data() ne $fields2[$i]->data()) {
                    $debug && warn "certainty 0 ", $fields1[$i]->data(), " ",
                        $fields2[$i]->data();
                    $certainty = 0;
                    last;
                }
            }
        }
    }

    return $certainty;
}

sub logger {
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime;
    my $time_msg = sprintf "[%04d-%02d-%02d %02d:%02d:%02d]",
        1900+$year, 1+$mon, $mday, $hour, $min, $sec;
    say $time_msg, ' ', @_;
}

sub print_usage {
    print <<_USAGE_;
$0: deduplicate authorities

Use this batch job to remove duplicate authorities

Parameters:
    --match <matchstring>

        matchstring is composed of : index1/tagsubfield1[##index2/tagsubfield2]
        the matching will be done with an AND between all elements of ONE
        matchstring.
        tagsubfield can be 123a or 123abc or 123.

        If multiple match parameters are sent, then it will try to match in the
        order it is provided to the script.

        Examples:
            at/152b##he-main/2..a##he/2..bxyzt##ident/009
            authtype/152b##he-main,ext/2..a##he,ext/2..bxyz
            sn,ne,st-numeric/001##authtype/152b##he-main,ext/2..a##he,ext/2..bxyz

        Match strings MUST contains at least one of the
        following indexes: he, he-main and ident


    --check <tag1><subfieldcodes>[,<tag2><subfieldcodes>[,...]]

        Check only these fields and subfields to determine whether two
        authorities are duplicates.

        <tag> is a three-digit number which represents the field tag, or the
        string 'TAG' which represents auth_tag_to_report and depends on
        authtypecode. You can use '.' as wildcards. E.g. '2..'

        <subfieldcodes> is a list of subfield codes, matching [0-9a-z]

        Examples:
            200abxyz will check subfields a,b,x,y,z of 200 fields
            009,152b will check 009 data and 152\$b subfields
            TAGab will check 250\$a and 250\$b if auth_tag_to_report is 250 for
                the type of the authority currently being checked

        Default: TAGabcdefghitxyz


    --choose-method <methods>

        Method(s) used to choose which authority to keep in case we found
        duplicates.
        <methods> is a string composed of letters describing what methods to use
        and in which order.
        Letters can be:
            d:  date, keep the most recent authority (based on 005 field)
            u:  usage, keep the most used authority
            p:  PPN (UNIMARC only), keep the authority with a ppn (when some
                authorities don't have one, based on 009 field)

        Examples:
            'pdu':  Among the authorities that have a PPN, keep the most recent,
                    and if two (or more) have the same date in 005, keep the
                    most used.

        Default is 'u'
        You cannot type more than 3 letters


    --where <sqlstring>     limit the deduplication to SOME authorities only

    --verbose               display logs

    --all                   deduplicate all authority type

    --help or -h            show this message.

Other paramters :
   Authtypecode to deduplicate authorities on
exemple:
    $0 --match ident/009 --match he-main,ext/200a##he,ext/200bxz NC

Note : If launched with DEBUG=1 it will print more messages
_USAGE_
}
