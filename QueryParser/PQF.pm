use strict;
use warnings;

package QueryParser::PQF;
use base 'QueryParser';

=head1 NAME

QueryParser::PQF - QueryParser driver for PQF

=head1 SYNOPSIS

    use QueryParser::PQF;
    my $QParser = QueryParser::PQF->new(%args);

=head1 DESCRIPTION

Main entrypoint into the QueryParser PQF driver. PQF is the Prefix Query
Language, the syntax used to serialize Z39.50 queries.

=head1 FUNCTIONS

=cut

=head2 bib1_field_map

    my $field_map = $QParser->bib1_field_map;
    $field_map->{'by_class'}{'author'}{'personal'} = { '1' => '1003' };
    $QParser->bib1_field_map($field_map);

Gets or sets the bib1 field mapping data structure.

=cut

sub bib1_field_map {
    my ($self, $map) = @_;

    $self->custom_data->{bib1_field_map} ||= {};
    $self->custom_data->{bib1_field_map} = $map if ($map);
    return $self->custom_data->{bib1_field_map};
}

=head2 add_bib1_field_map

    $QParser->add_bib1_field_map($server => $class => $field => \%attributes);

    $QParser->add_bib1_field_map('biblio' => 'author' => 'personal' =>
                                    { '1' => '1003' });

Adds a search field<->bib1 attribute mapping for the specified server. The
%attributes hash contains maps Bib-1 Attributes to the appropropriate
values. Not all attributes must be specified.

=cut

sub add_bib1_field_map {
    my ($self, $server, $class, $field, $attributes) = @_;

    my $attr_string = QueryParser::PQF::_util::attributes_to_attr_string($attributes);
    $attributes->{'attr_string'} = $attr_string;

    $self->add_search_field( $class => $field );
    $self->bib1_field_map->{$server}{'by_class'}{$class}{$field} = $attributes;
    $self->bib1_field_map->{$server}{'by_attr'}{$attr_string} = { 'classname' => $class, 'field' => $field, %$attributes };

    return $self->bib1_field_map;
}

=head2 bib1_field_by_attr

    my $field = $QParser->bib1_field_by_attr($server, \%attr);
    my $field = $QParser->bib1_field_by_attr('biblio', {'1' => '1003'});
    print $field->{'classname'}; # prints "author"
    print $field->{'field'}; # prints "personal"

Retrieve the search field used for the specified Bib-1 attribute set.

=cut

sub bib1_field_by_attr {
    my ($self, $server, $attributes) = @_;
    return unless ($server && $attributes);

    my $attr_string = QueryParser::PQF::_util::attributes_to_attr_string($attributes);

    return $self->bib1_field_by_attr_string($server, $attr_string);
}

=head2 bib1_field_by_attr_string

    my $field = $QParser->bib1_field_by_attr_string($server, $attr_string);
    my $field = $QParser->bib1_field_by_attr_string('biblio', '@attr 1=1003');
    print $field->{'classname'}; # prints "author"
    print $field->{'field'}; # prints "personal"

Retrieve the search field used for the specified Bib-1 attribute string
(i.e. PQF snippet).

=cut

sub bib1_field_by_attr_string {
    my ($self, $server, $attr_string) = @_;
    return unless ($server && $attr_string);

    return $self->bib1_field_map->{$server}{'by_attr'}{$attr_string};
}

=head2 bib1_field_by_class

    my $attributes = $QParser->bib1_field_by_class($server, $class, $field);
    my $attributes = $QParser->bib1_field_by_class('biblio', 'author', 'personal');
    my $attributes = $QParser->bib1_field_by_class('biblio', 'keyword', '');

Retrieve the Bib-1 attribute set associated with the specified search field. If
the field is not specified, the Bib-1 attribute set associated with the class
will be returned.

=cut

sub bib1_field_by_class {
    my ($self, $server, $class, $field) = @_;

    return unless ($server && $class);

    return $self->bib1_field_map->{$server}{'by_class'}{$class}{$field};
}

=head2 bib1_modifier_map

    my $modifier_map = $QParser->bib1_modifier_map;
    $modifier_map->{'by_name'}{'ascending'} = { '7' => '1' };
    $QParser->bib1_modifier_map($modifier_map);

Gets or sets the bib1 modifier mapping data structure.

=cut

sub bib1_modifier_map {
    my ($self, $map) = @_;

    $self->custom_data->{bib1_modifier_map} ||= {};
    $self->custom_data->{bib1_modifier_map} = $map if ($map);
    return $self->custom_data->{bib1_modifier_map};
}

=head2 add_bib1_modifier_map

    $QParser->add_bib1_modifier_map($server => $name => \%attributes);

    $QParser->add_bib1_modifier_map('biblio' => 'ascendin' =>
                                    { '7' => '1' });

Adds a search modifier<->bib1 attribute mapping for the specified server. The
%attributes hash contains maps Bib-1 Attributes to the appropropriate
values. Not all attributes must be specified.

=cut

sub add_bib1_modifier_map {
    my ($self, $server, $name, $attributes) = @_;

    my $attr_string = QueryParser::PQF::_util::attributes_to_attr_string($attributes);
    $attributes->{'attr_string'} = $attr_string;

    $self->add_search_modifier( $name );
    $self->bib1_modifier_map->{$server}{'by_name'}{$name} = $attributes;
    $self->bib1_modifier_map->{$server}{'by_attr'}{$attr_string} = { 'name' => $name, %$attributes };

    return $self->bib1_modifier_map;
}

=head2 bib1_modifier_by_attr

    my $modifier = $QParser->bib1_modifier_by_attr($server, \%attr);
    my $modifier = $QParser->bib1_modifier_by_attr('biblio', {'7' => '1'});
    print $field->{'name'}; # prints "ascending"

Retrieve the search modifier used for the specified Bib-1 attribute set.

=cut

sub bib1_modifier_by_attr {
    my ($self, $server, $attributes) = @_;
    return unless ($server && $attributes);

    my $attr_string = QueryParser::PQF::_util::attributes_to_attr_string($attributes);

    return $self->bib1_modifier_by_attr_string($server, $attr_string);
}

=head2 bib1_modifier_by_attr_string

    my $modifier = $QParser->bib1_modifier_by_attr_string($server, $attr_string);
    my $modifier = $QParser->bib1_modifier_by_attr_string('biblio', '@attr 7=1');
    print $field->{'name'}; # prints "ascending"

Retrieve the search modifier used for the specified Bib-1 attribute string
(i.e. PQF snippet).

=cut

sub bib1_modifier_by_attr_string {
    my ($self, $server, $attr_string) = @_;
    return unless ($server && $attr_string);

    return $self->bib1_modifier_map->{$server}{'by_attr'}{$attr_string};
}

=head2 bib1_modifier_by_name

    my $attributes = $QParser->bib1_modifier_by_name($server, $name);
    my $attributes = $QParser->bib1_modifier_by_name('biblio', 'ascending');

Retrieve the Bib-1 attribute set associated with the specified search modifier.

=cut

sub bib1_modifier_by_name {
    my ($self, $server, $name) = @_;

    return unless ($server && $name);

    return $self->bib1_modifier_map->{$server}{'by_name'}{$name};
}

=head2 target_syntax

    my $pqf = $QParser->target_syntax($server, [$query]);
    my $pqf = $QParser->target_syntax('biblio', 'author|personal:smith');
    print $pqf; # assuming all the indexes are configured,
                # prints '@attr 1=1003 @attr 4=6 "smith"'

Transforms the current or specified query into a PQF query string for the
specified server.

=cut

sub target_syntax {
    my ($self, $server, $query) = @_;
    my $pqf = '';
    $self->parse($query) if $query;
    return $self->parse_tree->target_syntax($server);
}

sub TEST_SETUP {
    my ($self) = @_;


    $self->default_search_class( 'keyword' );

    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'abstract' => { '1' => '62' } );
    $self->add_search_field_alias( 'keyword' => 'abstract' => 'ab' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => '' => { '1' => '1016' } );
    $self->add_search_field_alias( 'keyword' => '' => 'kw' );
    $self->add_bib1_field_map( 'biblioserver' => 'author' => '' => { '1' => '1003' } );
    $self->add_search_field_alias( 'author' => '' => 'au' );
    $self->add_bib1_field_map( 'biblioserver' => 'author' => 'personal' => { '1' => '1004' } );
    $self->add_bib1_field_map( 'biblioserver' => 'author' => 'corporate' => { '1' => '1005' } );
    $self->add_search_field_alias( 'author' => 'corporate' => 'cpn' );
    $self->add_bib1_field_map( 'biblioserver' => 'author' => 'conference' => { '1' => '1006' } );
    $self->add_search_field_alias( 'author' => 'conference' => 'cfn' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'local-classification' => { '1' => '20' } );
    $self->add_search_field_alias( 'keyword' => 'local-classification' => 'lcn' );
    $self->add_search_field_alias( 'keyword' => 'local-classification' => 'callnum' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'bib-level' => { '1' => '1021' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'code-institution' => { '1' => '56' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'language' => { '1' => '54' } );
    $self->add_search_field_alias( 'keyword' => 'language' => 'ln' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'record-type' => { '1' => '1001' } );
    $self->add_search_field_alias( 'keyword' => 'record-type' => 'rtype' );
    $self->add_search_field_alias( 'keyword' => 'record-type' => 'mc-rtype' );
    $self->add_search_field_alias( 'keyword' => 'record-type' => 'mus' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'content-type' => { '1' => '1034' } );
    $self->add_search_field_alias( 'keyword' => 'content-type' => 'ctype' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'lc-card-number' => { '1' => '9' } );
    $self->add_search_field_alias( 'keyword' => 'lc-card-number' => 'lc-card' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'local-number' => { '1' => '12' } );
    $self->add_search_field_alias( 'keyword' => 'local-number' => 'sn' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'copydate' => { '1' => '30' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'date-of-publication' => { '1' => 'pubdate' } );
    $self->add_search_field_alias( 'keyword' => 'date-of-publication' => 'yr' );
    $self->add_search_field_alias( 'keyword' => 'date-of-publication' => 'pubdate' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'date-of-acquisition' => { '1' => 'Date-of-acquisition' } );
    $self->add_search_field_alias( 'keyword' => 'date-of-acquisition' => 'acqdate' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'isbn' => { '1' => '7' } );
    $self->add_search_field_alias( 'keyword' => 'isbn' => 'nb' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'issn' => { '1' => '8' } );
    $self->add_search_field_alias( 'keyword' => 'issn' => 'ns' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'identifier-standard' => { '1' => '1007' } );
    $self->add_search_field_alias( 'keyword' => 'identifier-standard' => 'ident' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'upc' => { '1' => 'UPC' } );
    $self->add_search_field_alias( 'keyword' => 'upc' => 'upc' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'ean' => { '1' => 'EAN' } );
    $self->add_search_field_alias( 'keyword' => 'ean' => 'ean' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'music' => { '1' => 'Music-number' } );
    $self->add_search_field_alias( 'keyword' => 'music' => 'music' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'stock-number' => { '1' => '1028' } );
    $self->add_search_field_alias( 'keyword' => 'stock-number' => 'stock-number' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'material-type' => { '1' => '1031' } );
    $self->add_search_field_alias( 'keyword' => 'material-type' => 'material-type' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'place-publication' => { '1' => '59' } );
    $self->add_search_field_alias( 'keyword' => 'place-publication' => 'pl' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'personal-name' => { '1' => 'Personal-name' } );
    $self->add_search_field_alias( 'keyword' => 'personal-name' => 'pn' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'publisher' => { '1' => '1018' } );
    $self->add_search_field_alias( 'keyword' => 'publisher' => 'pb' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'note' => { '1' => '63' } );
    $self->add_search_field_alias( 'keyword' => 'note' => 'nt' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'record-control-number' => { '1' => '1045' } );
    $self->add_search_field_alias( 'keyword' => 'record-control-number' => 'rcn' );
    $self->add_bib1_field_map( 'biblioserver' => 'subject' => '' => { '1' => '21' } );
    $self->add_search_field_alias( 'subject' => '' => 'su' );
    $self->add_search_field_alias( 'subject' => '' => 'su-to' );
    $self->add_search_field_alias( 'subject' => '' => 'su-geo' );
    $self->add_search_field_alias( 'subject' => '' => 'su-ut' );
    $self->add_bib1_field_map( 'biblioserver' => 'subject' => 'name-personal' => { '1' => '1009' } );
    $self->add_search_field_alias( 'subject' => 'name-personal' => 'su-na' );
    $self->add_bib1_field_map( 'biblioserver' => 'title' => '' => { '1' => '4' } );
    $self->add_search_field_alias( 'title' => '' => 'ti' );
    $self->add_bib1_field_map( 'biblioserver' => 'title' => 'cover' => { '1' => '36' } );
    $self->add_search_field_alias( 'title' => 'cover' => 'title-cover' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'host-item' => { '1' => '1033' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'video-mt' => { '1' => 'Video-mt' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'graphics-type' => { '1' => 'Graphic-type' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'graphics-support' => { '1' => 'Graphic-support' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'type-of-serial' => { '1' => 'Type-Of-Serial' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'regularity-code' => { '1' => 'Regularity-code' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'material-type' => { '1' => 'Material-type' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'literature-code' => { '1' => 'Literature-Code' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'biography-code' => { '1' => 'Biography-code' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'illustration-code' => { '1' => 'Illustration-code' } );
    $self->add_bib1_field_map( 'biblioserver' => 'title' => 'series' => { '1' => '5' } );
    $self->add_search_field_alias( 'title' => 'series' => 'title-series' );
    $self->add_search_field_alias( 'title' => 'series' => 'se' );
    $self->add_bib1_field_map( 'biblioserver' => 'title' => 'uniform' => { '1' => 'Title-uniform' } );
    $self->add_search_field_alias( 'title' => 'uniform' => 'title-uniform' );
    $self->add_bib1_field_map( 'biblioserver' => 'subject' => 'authority-number' => { '1' => 'Koha-Auth-Number' } );
    $self->add_search_field_alias( 'subject' => 'authority-number' => 'an' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'control-number' => { '1' => '9001' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'biblionumber' => { '1' => '9002', '5' => '100' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'totalissues' => { '1' => '9003' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'cn-bib-source' => { '1' => '9004' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'cn-bib-sort' => { '1' => '9005' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'itemtype' => { '1' => '9006' } );
    $self->add_search_field_alias( 'keyword' => 'itemtype' => 'mc-itemtype' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'cn-class' => { '1' => '9007' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'cn-item' => { '1' => '9008' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'cn-prefix' => { '1' => '9009' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'cn-suffix' => { '1' => '9010' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'suppress' => { '1' => '9011' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'id-other' => { '1' => '9012' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'date-entered-on-file' => { '1' => 'date-entered-on-file' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'extent' => { '1' => 'Extent' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'llength' => { '1' => 'llength' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'summary' => { '1' => 'Summary' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'withdrawn' => { '1' => '8001' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'lost' => { '1' => '8002' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'classification-source' => { '1' => '8003' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'materials-specified' => { '1' => '8004' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'damaged' => { '1' => '8005' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'restricted' => { '1' => '8006' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'cn-sort' => { '1' => '8007' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'notforloan' => { '1' => '8008', '4' => '109' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'ccode' => { '1' => '8009' } );
    $self->add_search_field_alias( 'keyword' => 'ccode' => 'mc-ccode' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'itemnumber' => { '1' => '8010' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'homebranch' => { '1' => 'homebranch' } );
    $self->add_search_field_alias( 'keyword' => 'homebranch' => 'branch' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'holdingbranch' => { '1' => '8012' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'location' => { '1' => '8013' } );
    $self->add_search_field_alias( 'keyword' => 'location' => 'mc-loc' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'acqsource' => { '1' => '8015' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'coded-location-qualifier' => { '1' => '8016' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'price' => { '1' => '8017' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'stocknumber' => { '1' => '1062' } );
    $self->add_search_field_alias( 'keyword' => 'stocknumber' => 'inv' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'stack' => { '1' => '8018' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'issues' => { '1' => '8019' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'renewals' => { '1' => '8020' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'reserves' => { '1' => '8021' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'local-classification' => { '1' => '8022' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'barcode' => { '1' => '8023' } );
    $self->add_search_field_alias( 'keyword' => 'barcode' => 'bc' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'onloan' => { '1' => '8024' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'datelastseen' => { '1' => '8025' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'datelastborrowed' => { '1' => '8026' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'copynumber' => { '1' => '8027' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'uri' => { '1' => '8028' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'replacementprice' => { '1' => '8029' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'replacementpricedate' => { '1' => '8030' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'itype' => { '1' => '8031' } );
    $self->add_search_field_alias( 'keyword' => 'itype' => 'mc-itype' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'ff8-22' => { '1' => '8822' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'ff8-23' => { '1' => '8823' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'ff8-34' => { '1' => '8834' } );
# Audience
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'audience' => { '1' => '8822' } );
    $self->add_search_field_alias( 'keyword' => 'audience' => 'aud' );

# Content and Literary form
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'fiction' => { '1' => '8833' } );
    $self->add_search_field_alias( 'keyword' => 'fiction' => 'fic' );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'biography' => { '1' => '8834' } );
    $self->add_search_field_alias( 'keyword' => 'biography' => 'bio' );

# Format
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'format' => { '1' => '8823' } );
# format used as a limit FIXME: needed?
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'l-format' => { '1' => '8703' } );

    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'illustration-code' => { '1' => 'Illustration-code ' } );

# Lexile Number
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'lex' => { '1' => '9903 r=r' } );

#Accelerated Reader Level
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'arl' => { '1' => '9904 r=r' } );

#Accelerated Reader Point
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'arp' => { '1' => '9013 r=r' } );

# Curriculum
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'curriculum' => { '1' => '9658' } );

## Statuses
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'popularity' => { '1' => 'issues' } );

## Type Limits
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'dt-bks' => { '1' => '8700' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'dt-vis' => { '1' => '8700' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'dt-sr' => { '1' => '8700' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'dt-cf' => { '1' => '8700' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'dt-map' => { '1' => '8700' } );

    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'name' => { '1' => '1002' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'item' => { '1' => '9520' } );
    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'host-item-number' => { '1' => '8911' } );
    $self->add_search_field_alias( 'keyword' => 'host-item-number' => 'hi' );

    $self->add_bib1_field_map( 'biblioserver' => 'keyword' => 'alwaysmatch' => { '1' => '_ALLRECORDS', '2' => '103' } );
    $self->add_bib1_field_map( 'biblioserver' => 'subject' => 'complete' => { '1' => '21', '3' => '1', '4' => '1', '5' => '100', '6' => '3' } );

    $self->add_bib1_modifier_map( 'biblioserver' => 'title-sort-za' => { '7' => '2', '1' => '36', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map( 'biblioserver' => 'title-sort-az' => { '7' => '1', '1' => '36', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map( 'biblioserver' => 'ascending' => { '7' => '1' } );
    $self->add_bib1_modifier_map( 'biblioserver' => 'descending' => { '7' => '2' } );

    $self->add_bib1_field_map( 'authorityserver' => 'subject' => 'headingmain' => { '1' => 'Heading-Main' } );
    $self->add_bib1_field_map( 'authorityserver' => 'subject' => 'heading' => { '1' => 'Heading' } );
    $self->add_bib1_field_map( 'authorityserver' => 'subject' => 'matchheading' => { '1' => 'Match-heading' } );
    $self->add_bib1_field_map( 'authorityserver' => 'subject' => 'seefrom' => { '1' => 'Match-heading-see-from' } );
    $self->add_bib1_field_map( 'authorityserver' => 'subject' => '' => { '1' => 'Match-heading' } );
    $self->add_bib1_field_map( 'authorityserver' => 'keyword' => 'alwaysmatch' => { '1' => '_ALLRECORDS', '2' => '103' } );
    $self->add_bib1_field_map( 'authorityserver' => 'keyword' => 'match' => { '1' => 'Match' } );
    $self->add_bib1_field_map( 'authorityserver' => 'keyword' => 'thesaurus' => { '1' => 'Subject-heading-thesaurus' } );
    $self->add_bib1_field_map( 'authorityserver' => 'keyword' => 'authtype' => { '1' => 'authtype', '5' => '100' } );
    $self->add_bib1_field_map( 'authorityserver' => 'keyword' => '' => { '1' => 'Any' } );
    $self->add_search_field_alias( 'subject' => 'headingmain' => 'mainmainentry' );
    $self->add_search_field_alias( 'subject' => 'heading' => 'mainentry' );
    $self->add_search_field_alias( 'subject' => 'heading' => 'he' );
    $self->add_search_field_alias( 'subject' => 'matchheading' => 'match-heading' );
    $self->add_search_field_alias( 'keyword' => '' => 'any' );
    $self->add_search_field_alias( 'keyword' => 'match' => 'match' );
    $self->add_search_field_alias( 'subject' => 'seefrom' => 'see-from' );
    $self->add_search_field_alias( 'keyword' => 'thesaurus' => 'thesaurus' );
    $self->add_search_field_alias( 'keyword' => 'alwaysmatch' => 'all' );
    $self->add_search_field_alias( 'keyword' => 'authtype' => 'authtype' );
    $self->add_search_field_alias( 'keyword' => 'authtype' => 'at' );

    $self->add_bib1_field_map( 'authorityserver' => 'subject' => 'start' => { '3' => '2', '4' => '1', '5' => '1' } );
    $self->add_bib1_field_map( 'authorityserver' => 'subject' => 'exact' => { '4' => '1', '5' => '100', '6' => '3' } );

    $self->add_bib1_modifier_map( 'authorityserver' => 'HeadingAsc' => { '7' => '1', '1' => 'Heading', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map( 'authorityserver' => 'HeadingDsc' => { '7' => '2', '1' => 'Heading', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map( 'authorityserver' => 'AuthidAsc' => { '7' => '1', '1' => 'Local-Number', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map( 'authorityserver' => 'AuthidDsc' => { '7' => '2', '1' => 'Local-Number', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map( 'authorityserver' => 'Relevance' => { '2' => '102' } );

    return $self;
}

#-------------------------------
package QueryParser::PQF::query_plan;
use base 'QueryParser::query_plan';

=head2 QueryParser::PQF::query_plan::target_syntax

    my $pqf = $query_plan->target_syntax($server);

Transforms a QueryParser::query_plan object into PQF. Do not use directly.

=cut

sub target_syntax {
    my ($self, $server) = @_;
    my $pqf = '';
    my $node_pqf;
    my $node_count = 0;

    for my $node ( @{$self->query_nodes} ) {

        if (ref($node)) {
            $node_pqf = $node->target_syntax($server);
            $node_count++ if $node_pqf;
            $pqf .= $node_pqf;
        }
    }
    $pqf = ($self->joiner eq '|' ? ' @or ' : ' @and ') x ($node_count - 1) . $pqf;
    foreach my $modifier ( @{$self->modifiers} ) {
        my $modifierpqf = $modifier->target_syntax($server, $self);
        $pqf = $modifierpqf . ' ' . $pqf if $modifierpqf;
    }
    return $pqf;
}

#-------------------------------
package QueryParser::PQF::query_plan::filter;
use base 'QueryParser::query_plan::filter';

=head2 QueryParser::PQF::query_plan::filter::target_syntax

    my $pqf = $filter->target_syntax($server);

Transforms a QueryParser::query_plan::filter object into PQF. Do not use
directly.

=cut

sub target_syntax {
    my ($self, $server) = @_;

    return '';
}

#-------------------------------
package QueryParser::PQF::query_plan::facet;
use base 'QueryParser::query_plan::facet';

=head2 QueryParser::PQF::query_plan::facet::target_syntax

    my $pqf = $facet->target_syntax($server);

Transforms a QueryParser::query_plan::facet object into PQF. Do not use
directly.

=cut

sub target_syntax {
    my ($self, $server) = @_;

    return '';
}

#-------------------------------
package QueryParser::PQF::query_plan::modifier;
use base 'QueryParser::query_plan::modifier';

=head2 QueryParser::PQF::query_plan::modifier::target_syntax

    my $pqf = $modifier->target_syntax($server, $query_plan);

Transforms a QueryParser::query_plan::modifier object into PQF. Do not use
directly. The second argument points ot the query_plan, since modifiers do
not have a reference to their parent query_plan.

=cut

sub target_syntax {
    my ($self, $server, $query_plan) = @_;
    my $pqf = '';
    my @fields;

    my $attributes = $query_plan->QueryParser->bib1_modifier_by_name($server, $self->name);
    $pqf = $attributes->{'op'} . ' ' . ($self->{'negate'} ? '@not ' : '') . $attributes->{'attr_string'};
    return $pqf;
}

#-------------------------------
package QueryParser::PQF::query_plan::node::atom;
use base 'QueryParser::query_plan::node::atom';

=head2 QueryParser::PQF::query_plan::node::atom::target_syntax

    my $pqf = $atom->target_syntax($server);

Transforms a QueryParser::query_plan::node::atom object into PQF. Do not use
directly.

=cut

sub target_syntax {
    my ($self, $server) = @_;

    return ' "' .  $self->content . '" ';
}

#-------------------------------
package QueryParser::PQF::query_plan::node;
use base 'QueryParser::query_plan::node';

=head2 QueryParser::query_plan::node::target_syntax

    my $pqf = $node->target_syntax($server);

Transforms a QueryParser::query_plan::node object into PQF. Do not use directly.

=cut

sub target_syntax {
    my ($self, $server) = @_;
    my $pqf = '';
    my $atom_content;
    my $atom_count = 0;
    my @fields;

    if (scalar(@{$self->fields})) {
        foreach my $field (@{$self->fields}) {
            push @fields, $self->plan->QueryParser->bib1_field_by_class($server, $self->classname, $field)
        }
    } else {
        push @fields, $self->plan->QueryParser->bib1_field_by_class($server, $self->classname, '')
    }

    if (@{$self->phrases}) {
        foreach my $phrase (@{$self->phrases}) {
            if ($phrase) {
                $pqf .= ' @or ' x (scalar(@fields) - 1);
                foreach my $attributes (@fields) {
                    $pqf .= $attributes->{'attr_string'} . ($attributes->{'4'} ? '' : ' @attr 4=1 ') . ' "' . $phrase . '" ';
                }
                $atom_count++;
            }
        }
    } else {
        foreach my $atom (@{$self->query_atoms}) {
            if (ref($atom)) {
                $atom_content = $atom->target_syntax($server);
                if ($atom_content) {
                    $pqf .= ' @or ' x (scalar(@fields) - 1);
                    foreach my $attributes (@fields) {
                        $pqf .= $attributes->{'attr_string'} . ($attributes->{'4'} ? '' : ' @attr 4=6 ') . $atom_content . ' ';
                    }
                    $atom_count++;
                }
            }
        }
    }
    $pqf = (QueryParser::_util::default_joiner eq '|' ? ' @or ' : ' @and ') x ($atom_count - 1) . $pqf;
    return $pqf;
}

package QueryParser::PQF::_util;

sub attributes_to_attr_string {
    my ($attributes) = @_;
    my $attr_string = '';
    my $key;
    my $value;
    while (($key, $value) = each(%$attributes)) {
        next unless ($key and $key ne 'op');
        $attr_string .= ' @attr ' . $key . '=' . $value . ' ';
    }
    $attr_string =~ s/^\s*//;
    $attr_string =~ s/\s*$//;
    $attr_string .= ' ' . $attributes->{''} if defined $attributes->{''};
    return $attr_string;
}

1;
