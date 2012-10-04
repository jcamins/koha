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

    my $attr_string = '';
    my $key;
    my $value;
    while (($key, $value) = each(%$attributes)) {
        $attr_string .= ' @attr ' . $key . '=' . $value . ' ';
    }
    $attr_string =~ s/^\s*//;
    $attr_string =~ s/\s*$//;
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

    my $attr_string = '';
    my $key;
    my $value;
    while (($key, $value) = each(%$attributes)) {
        $attr_string .= ' @attr ' . $key . '=' . $value . ' ';
    }
    $attr_string =~ s/^\s*//;
    $attr_string =~ s/\s*$//;

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

    my $pqf = $modifier->target_syntax($server);

Transforms a QueryParser::query_plan::modifier object into PQF. Do not use
directly.

=cut

sub target_syntax {
    my ($self, $server) = @_;

    return '';
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

1;
