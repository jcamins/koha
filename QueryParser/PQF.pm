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

    $self->add_search_class_alias( title => 'ti' );
#    $self->add_search_class_alias( author => 'au' );
#    $self->add_search_class_alias( author => 'name' );
    $self->add_search_class_alias( author => 'dc.contributor' );
    $self->add_search_class_alias( subject => 'su' );
    $self->add_search_class_alias( subject => 'bib.subject(?:Title|Place|Occupation)' );
    $self->add_search_class_alias( series => 'se' );
    $self->add_search_class_alias( keyword => 'dc.identifier' );

#    $self->add_query_normalizer( author => corporate => 'search_normalize' );
#    $self->add_query_normalizer( keyword => keyword => 'search_normalize' );

#    $self->add_search_field_alias( subject => name => 'bib.subjectName' );
#    $self->add_search_field_alias( subject => name => 'nomen' );

#    $self->add_search_field( 'author' => 'personal' );
#    $self->add_search_field( 'author' => 'corporate' );
#    $self->add_search_field( 'author' => 'meeting' );

    $self->default_search_class( 'keyword' );

    # will be retained simply for back-compat
#    $self->add_search_filter( 'format' );

    # grumble grumble, special cases against date1 and date2
#   $self->add_search_filter( 'before' );
#   $self->add_search_filter( 'after' );
#   $self->add_search_filter( 'between' );
#   $self->add_search_filter( 'during' );

    # used by layers above this
#   $self->add_search_filter( 'statuses' );
#   $self->add_search_filter( 'locations' );
#   $self->add_search_filter( 'location_groups' );
#   $self->add_search_filter( 'site' );
#   $self->add_search_filter( 'pref_ou' );
#   $self->add_search_filter( 'lasso' );
#   $self->add_search_filter( 'my_lasso' );
#   $self->add_search_filter( 'depth' );
#   $self->add_search_filter( 'language' );
#   $self->add_search_filter( 'offset' );
#   $self->add_search_filter( 'limit' );
#   $self->add_search_filter( 'check_limit' );
#   $self->add_search_filter( 'skip_check' );
#   $self->add_search_filter( 'superpage' );
#   $self->add_search_filter( 'estimation_strategy' );
#   $self->add_search_modifier( 'available' );
#   $self->add_search_modifier( 'staff' );

    # Start from container data (bre, acn, acp): container(bre,bookbag,123,deadb33fdeadb33fdeadb33fdeadb33f)
#   $self->add_search_filter( 'container' );

    # Start from a list of record ids, either bre or metarecords, depending on the #metabib modifier
#   $self->add_search_filter( 'record_list' );

    # used internally, but generally not user-settable
#   $self->add_search_filter( 'preferred_language' );
#   $self->add_search_filter( 'preferred_language_weight' );
#   $self->add_search_filter( 'preferred_language_multiplier' );
#   $self->add_search_filter( 'core_limit' );

    # XXX Valid values to be supplied by SVF
#   $self->add_search_filter( 'sort' );

    # modifies core query, not configurable
#   $self->add_search_modifier( 'descending' );
#   $self->add_search_modifier( 'ascending' );
#   $self->add_search_modifier( 'nullsfirst' );
#   $self->add_search_modifier( 'nullslast' );
#   $self->add_search_modifier( 'metarecord' );
#   $self->add_search_modifier( 'metabib' );

#    $self->add_facet_field( 'author' => 'personal' );
#   $self->add_facet_field( 'author' => 'corporate' );
#   $self->add_facet_field( 'subject' => 'topic' );
#   $self->add_facet_field( 'subject' => 'geographic' );

#   $self->add_search_filter( 'testfilter', \&test_filter_callback );

    $self->add_bib1_field_map( 'biblio' => 'keyword' => '' => { '1' => '1016' } );
    $self->add_bib1_field_map( 'biblio' => 'author' => '' => { '1' => '1003' } );
    $self->add_bib1_field_map( 'biblio' => 'author' => 'personal' => { '1' => '1004' } );
    $self->add_bib1_field_map( 'biblio' => 'author' => 'corporate' => { '1' => '1005' } );
    $self->add_bib1_field_map( 'biblio' => 'keyword' => 'alwaysmatch' => { '1' => '_ALLRECORDS', '2' => '103' } );
    $self->add_bib1_field_map( 'biblio' => 'subject' => 'complete' => { '1' => '21', '3' => '1', '4' => '1', '5' => '100', '6' => '3' } );

    $self->add_bib1_field_map( 'authority' => 'subject' => 'headingmain' => { '1' => 'Heading-Main' } );
    $self->add_bib1_field_map( 'authority' => 'subject' => 'heading' => { '1' => 'Heading' } );
    $self->add_bib1_field_map( 'authority' => 'subject' => 'matchheading' => { '1' => 'Match-heading' } );
    $self->add_bib1_field_map( 'authority' => 'subject' => 'seefrom' => { '1' => 'Match-heading-see-from' } );
    $self->add_bib1_field_map( 'authority' => 'subject' => '' => { '1' => 'Match-heading' } );
    $self->add_bib1_field_map( 'authority' => 'keyword' => 'alwaysmatch' => { '1' => '_ALLRECORDS', '2' => '103' } );
    $self->add_bib1_field_map( 'authority' => 'keyword' => 'match' => { '1' => 'Match' } );
    $self->add_bib1_field_map( 'authority' => 'keyword' => 'thesaurus' => { '1' => 'Subject-heading-thesaurus' } );
    $self->add_bib1_field_map( 'authority' => 'keyword' => 'authtype' => { '1' => 'authtype', '5' => '100' } );
    $self->add_bib1_field_map( 'authority' => 'keyword' => '' => { '1' => 'Any' } );
    $self->add_search_field_alias( 'subject' => 'headingmain' => 'mainmainentry' );
    $self->add_search_field_alias( 'subject' => 'heading' => 'mainentry' );
    $self->add_search_field_alias( 'subject' => 'matchheading' => 'match-heading' );
    $self->add_search_field_alias( 'keyword' => '' => 'any' );
    $self->add_search_field_alias( 'keyword' => 'match' => 'match' );
    $self->add_search_field_alias( 'subject' => 'seefrom' => 'see-from' );
    $self->add_search_field_alias( 'keyword' => 'thesaurus' => 'thesaurus' );
    $self->add_search_field_alias( 'keyword' => 'alwaysmatch' => 'all' );
    $self->add_search_field_alias( 'keyword' => 'authtype' => 'authtype' );

    $self->add_bib1_field_map( 'authority' => 'subject' => 'start' => { '3' => '2', '4' => '1', '5' => '1' } );
    $self->add_bib1_field_map( 'authority' => 'subject' => 'exact' => { '4' => '1', '5' => '100', '6' => '3' } );

    $self->add_bib1_modifier_map( 'authority' => 'HeadingAsc' => { '7' => '1', '1' => 'Heading', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map( 'authority' => 'HeadingDsc' => { '7' => '2', '1' => 'Heading', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map( 'authority' => 'AuthidAsc' => { '7' => '1', '1' => 'Local-Number', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map( 'authority' => 'AuthidDsc' => { '7' => '2', '1' => 'Local-Number', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map( 'authority' => 'Relevance' => { '2' => '102' } );

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
