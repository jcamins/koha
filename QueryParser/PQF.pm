use strict;
use warnings;

package QueryParser::PQF;
use base 'QueryParser';

sub bib1_field_map {
    my ($self, $map) = @_;

    $self->custom_data->{bib1_field_map} ||= {};
    $self->custom_data->{bib1_field_map} = $map if ($map);
    return $self->custom_data->{bib1_field_map};
}

sub add_bib1_field_map {
    my ($self, $server, $class, $field, $attributes) = @_;

    my $attr_string = '';
    my $key;
    my $value;
    while (($key, $value) = each(%$attributes)) {
        $attr_string .= ' @attr ' . $key . '=' . $value . ' ';
    }
    $attributes->{'attr_string'} = $attr_string;

    my $use_attr1 = $attributes->{1};
    $self->add_search_field( $class => $field );
    $self->bib1_field_map->{$server}{'by_class'}{$class}{$field} = $attributes;
    $self->bib1_field_map->{$server}{'by_attr'}{$use_attr1} = { 'classname' => $class, 'field' => $field } if $use_attr1;

    return $self->bib1_field_map;
}

sub bib1_field_by_attr {
    my ($self, $server, $attr) = @_;

    return unless ($server && $attr);

    return $self->bib1_field_map->{$server}{'by_attr'}{$attr};
}

sub bib1_field_by_class {
    my ($self, $server, $class, $field) = @_;

    return unless ($server && $class);

    return $self->bib1_field_map->{$server}{'by_class'}{$class}{$field};
}

sub target_syntax {
    my ($self, $server, $query) = @_;
    my $pqf = '';
    $self->parse($query) if $query;
    return $self->parse_tree->target_syntax($server);
}

#-------------------------------
package QueryParser::PQF::query_plan;
use base 'QueryParser::query_plan';

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

#-------------------------------
package QueryParser::PQF::query_plan::facet;
use base 'QueryParser::query_plan::facet';

#-------------------------------
package QueryParser::PQF::query_plan::modifier;
use base 'QueryParser::query_plan::modifier';

#-------------------------------
package QueryParser::PQF::query_plan::node::atom;
use base 'QueryParser::query_plan::node::atom';

sub target_syntax {
    my ($self, $server) = @_;
    my $pqf = '';

    return ' "' .  $self->content . '" ';
}

#-------------------------------
package QueryParser::PQF::query_plan::node;
use base 'QueryParser::query_plan::node';

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
