use strict;
use warnings;

package QueryParser::PQF;
use base qw(QueryParser Class::Accessor);

use Module::Load::Conditional qw(can_load);


=head1 NAME

QueryParser::PQF - QueryParser driver for PQF

=head1 SYNOPSIS

    use QueryParser::PQF;
    my $QParser = QueryParser::PQF->new(%args);

=head1 DESCRIPTION

Main entrypoint into the QueryParser PQF driver. PQF is the Prefix Query
Language, the syntax used to serialize Z39.50 queries.

=head1 ACCESSORS

In order to simplify Bib-1 attribute mapping, this driver uses Class::Accessor
for accessing the following maps:

=over 4

=item B<bib1_field_map> - search class/field Bib-1 mappings

=item B<bib1_modifier_map> - search modifier mappings

=item B<bib1_filter_map> - search filter mappings

=item B<bib1_relevance_bump_map> - relevance bump mappings

=back

=cut

__PACKAGE__->mk_accessors(qw(bib1_field_map bib1_modifier_map bib1_filter_map bib1_relevance_bump_map));

=head1 FUNCTIONS

=cut

=head2 get

Overridden accessor method for Class::Accessor. (Do not call directly)

=cut

sub get {
    my $self = shift;
    return $self->_map(@_);
}

=head2 set

Overridden mutator method for Class::Accessor. (Do not call directly)

=cut

sub set {
    my $self = shift;
    return $self->_map(@_);
}

=head2 add_bib1_field_map

    $QParser->add_bib1_field_map($class => $field => $server => \%attributes);

    $QParser->add_bib1_field_map('author' => 'personal' => 'biblioserver' =>
                                    { '1' => '1003' });

Adds a search field<->bib1 attribute mapping for the specified server. The
%attributes hash contains maps Bib-1 Attributes to the appropropriate
values. Not all attributes must be specified.

=cut

sub add_bib1_field_map {
    my ($self, $class, $field, $server, $attributes) = @_;

    $self->add_search_field( $class => $field );
    $self->add_search_field_alias( $class => $field => $field );
    return $self->_add_field_mapping($self->bib1_field_map, $class, $field, $server, $attributes);
}

=head2 add_bib1_modifier_map

    $QParser->add_bib1_modifier_map($name => $server => \%attributes);

    $QParser->add_bib1_modifier_map('ascending' => 'biblioserver' =>
                                    { '7' => '1' });

Adds a search modifier<->bib1 attribute mapping for the specified server. The
%attributes hash contains maps Bib-1 Attributes to the appropropriate
values. Not all attributes must be specified.

=cut

sub add_bib1_modifier_map {
    my ($self, $name, $server, $attributes) = @_;

    $self->add_search_modifier( $name );

    return $self->_add_mapping($self->bib1_modifier_map, $name, $server, $attributes);
}

=head2 add_bib1_filter_map

    $QParser->add_bib1_filter_map($name => $server => \%attributes);

    $QParser->add_bib1_filter_map('date' => 'biblioserver' =>
                                    { 'callback' => &_my_callback });

Adds a search filter<->bib1 attribute mapping for the specified server. The
%attributes hash maps Bib-1 Attributes to the appropropriate values and
provides a callback for the filter. Not all attributes must be specified.

=cut

sub add_bib1_filter_map {
    my ($self, $name, $server, $attributes) = @_;

    $self->add_search_filter( $name, $attributes->{'callback'} );

    return $self->_add_mapping($self->bib1_filter_map, $server, $name, $attributes);
}

=head2 add_relevance_bump

    $QParser->add_relevance_bump($class, $field, $server, $multiplier, $active);
    $QParser->add_relevance_bump('title' => 'exact' => 'biblioserver' => 34, 1);

Add a relevance bump to the specified field. When searching for a class without
any fields, all the relevance bumps for the specified class will be 'OR'ed
together.

=cut

sub add_relevance_bump {
    my ($self, $class, $field, $server, $multiplier, $active) = @_;
    my $attributes = { '9' => $multiplier, '2' => '102', 'active' => $active };

    $self->add_search_field( $class => $field );
    return $self->_add_field_mapping($self->bib1_relevance_bump_map, $class, $field, $server, $attributes);
}


=head2 target_syntax

    my $pqf = $QParser->target_syntax($server, [$query]);
    my $pqf = $QParser->target_syntax('biblioserver', 'author|personal:smith');
    print $pqf; # assuming all the indexes are configured,
                # prints '@attr 1=1003 @attr 4=6 "smith"'

Transforms the current or specified query into a PQF query string for the
specified server.

=cut

sub target_syntax {
    my ($self, $server, $query) = @_;
    my $pqf = '';
    $self->parse($query) if $query;
    warn "QP query for $server: " . $self->query . "\n" if $self->debug;
    $pqf = $self->parse_tree->target_syntax($server);
    warn "PQF query: $pqf\n" if $self->debug;
    return $pqf;
}

=head2 date_filter_target_callback

    $QParser->add_bib1_filter_map($server, { 'target_syntax_callback' => \&QueryParser::PQF::date_filter_target_callback, '1' => 'pubdate' });

Callback for date filters. Note that although the first argument is the QParser
object, this is technically not an object-oriented routine. This has no
real-world implications.

=cut

sub date_filter_target_callback {
    my ($QParser, $filter, $params, $negate, $server) = @_;
    my $attr_string = $QParser->bib1_mapping_by_name( 'filter', $server, $filter )->{'attr_string'};
    my $pqf = '';
    foreach my $datespec (@$params) {
        my $datepqf = '';
        if ($datespec) {
            if ($datespec =~ m/(.*)-(.*)/) {
                if ($1) {
                    $datepqf .= $attr_string . ' @attr 2=4 "' . $1 . '"';
                }
                if ($2) {
                    $datepqf .= $attr_string . ' @attr 2=2 "' . $2 . '"';
                    $datepqf = '@and ' . $datepqf if $1;
                }
            } else {
                $datepqf .= $attr_string . ' "' . $datespec . '"';
            }
        }
        $pqf = ' @or ' . ($negate ? '@not @attr 1=_ALLRECORDS @attr 2=103 "" ' : '') . $pqf if $pqf;
        $pqf .= $datepqf;
    }
    return $pqf;
}

=head2 _map

    return $self->_map('bib1_field_map', $map);

Retrieves or sets a map.

=cut

sub _map {
    my ($self, $name, $map) = @_;
    $self->custom_data->{$name} ||= {};
    $self->custom_data->{$name} = $map if ($map);
    return $self->custom_data->{$name};
}

=head2 _add_mapping

    return $self->_add_mapping($map, $name, $server, $attributes)

Adds a mapping. Note that this is not used for mappings relating to fields.

=cut

sub _add_mapping {
    my ($self, $map, $name, $server, $attributes) = @_;

    my $attr_string = QueryParser::PQF::_util::attributes_to_attr_string($attributes);
    $attributes->{'attr_string'} = $attr_string;

    $map->{'by_name'}{$name}{$server} = $attributes;
    $map->{'by_attr'}{$server}{$attr_string} = { 'name' => $name, %$attributes };

    return $map;
}

=head2 _add_field_mapping

    return $self->_add_field_mapping($map, $class, $field, $server, $attributes)

Adds a mapping for field-related data.

=cut

sub _add_field_mapping {
    my ($self, $map, $class, $field, $server, $attributes) = @_;
    my $attr_string = QueryParser::PQF::_util::attributes_to_attr_string($attributes);
    $attributes->{'attr_string'} = $attr_string;

    $map->{'by_name'}{$class}{$field}{$server} = $attributes;
    $map->{'by_attr'}{$server}{$attr_string} = { 'classname' => $class, 'field' => $field, %$attributes };
    return $map;
}


=head2 bib1_mapping_by_name

    my $attributes = $QParser->bib1_mapping_by_name($type, $name[, $subname], $server);
    my $attributes = $QParser->bib1_mapping_by_name('field', 'author', 'personal', 'biblioserver');
    my $attributes = $QParser->bib1_mapping_by_name('filter', 'pubdate', 'biblioserver');

Retrieve the Bib-1 attribute set associated with the specified mapping.
=cut

sub bib1_mapping_by_name {
    my $server = pop;
    my ($self, $type, $name, $field) = @_;

    return unless ($server && $name);
    return unless ($type eq 'field' || $type eq 'modifier' || $type eq 'filter' || $type eq 'relevance_bump');
    if ($type eq 'field') {
    # Unfortunately field is a special case thanks to the class->field hierarchy
        return $self->_map('bib1_' . $type . '_map')->{'by_name'}{$name}{$field}{$server};
    } else {
        return $self->_map('bib1_' . $type . '_map')->{'by_name'}{$name}{$server};
    }
}

=head2 bib1_mapping_by_attr

    my $field = $QParser->bib1_mapping_by_attr($type, $server, \%attr);
    my $field = $QParser->bib1_mapping_by_attr('field', 'biblioserver', {'1' => '1003'});
    print $field->{'classname'}; # prints "author"
    print $field->{'field'}; # prints "personal"

Retrieve the search field/modifier/filter used for the specified Bib-1 attribute set.

=cut

sub bib1_mapping_by_attr {
    my ($self, $type, $server, $attributes) = @_;
    return unless ($server && $attributes);

    my $attr_string = QueryParser::PQF::_util::attributes_to_attr_string($attributes);

    return $self->bib1_mapping_by_attr_string($type, $server, $attr_string);
}

=head2 bib1_mapping_by_attr_string

    my $field = $QParser->bib1_mapping_by_attr_string($type, $server, $attr_string);
    my $field = $QParser->bib1_mapping_by_attr_string('field', 'biblioserver', '@attr 1=1003');
    print $field->{'classname'}; # prints "author"
    print $field->{'field'}; # prints "personal"

Retrieve the search field/modifier/filter used for the specified Bib-1 attribute string
(i.e. PQF snippet).

=cut

sub bib1_mapping_by_attr_string {
    my ($self, $type, $server, $attr_string) = @_;
    return unless ($server && $attr_string);
    return unless ($type eq 'field' || $type eq 'modifier' || $type eq 'filter' || $type eq 'relevance_bump');

    return $self->_map('bib1_' . $type . '_map')->{'by_attr'}{$server}{$attr_string};
}


=head2 _canonicalize_field_map

Convert a field map into its canonical form for serialization. Used only for
fields and relevance bumps.

=cut

sub _canonicalize_field_map {
    my ( $map, $aliases ) = @_;
    my $canonical_map = {};

    foreach my $class ( keys %{ $map->{'by_name'} } ) {
        $canonical_map->{$class} ||= {};
        foreach my $field ( keys %{ $map->{'by_name'}->{$class} } ) {
            my $field_map = {
                'index'   => $field,
                'label'   => ucfirst($field),
                'enabled' => '1',
            };
            foreach
              my $server ( keys %{ $map->{'by_name'}->{$class}->{$field} } )
            {
                $field_map->{'bib1_mapping'} ||= {};
                $field_map->{'bib1_mapping'}->{$server} =
                  $map->{'by_name'}->{$class}->{$field}->{$server};
                delete $field_map->{'bib1_mapping'}->{$server}->{'attr_string'}
                  if defined(
                          $field_map->{'bib1_mapping'}->{$server}
                            ->{'attr_string'}
                  );
            }
            if ($aliases) {
                $field_map->{'aliases'} = [];
                foreach my $alias ( @{ $aliases->{$class}->{$field} } ) {
                    push @{ $field_map->{$class}->{$field}->{'aliases'} },
                      $alias;
                }
            }
            $canonical_map->{$class}->{$field} = $field_map;
        }
    }
    return $canonical_map;
}

=head2 _canonicalize_map

Convert a map into its canonical form for serialization. Not used for fields.

=cut

sub _canonicalize_map {
    my ($map) = @_;
    my $canonical_map = {};

    foreach my $name ( keys %{ $map->{'by_name'} } ) {
        $canonical_map->{$name} = {
            'label'        => ucfirst($name),
            'enabled'      => 1,
            'bib1_mapping' => {}
        };
        foreach my $server ( keys %{ $map->{'by_name'}->{$name} } ) {
            $canonical_map->{$name}->{'bib1_mapping'}->{$server} =
              $map->{'by_name'}->{$name}->{$server};
            delete $canonical_map->{$name}->{'bib1_mapping'}->{$server}
              ->{'attr_string'}
              if defined(
                      $canonical_map->{$name}->{'bib1_mapping'}->{$server}
                        ->{'attr_string'}
              );
        }
    }
    return $canonical_map;
}

=head2 serialize_mappings

    my $yaml = $QParser->serialize_mappings;
    my $json = $QParser->serialze_mappings('json');

Serialize Bib-1 mappings to YAML or JSON.

=cut

sub serialize_mappings {
    my ( $self, $format ) = @_;
    $format ||= 'yaml';
    my $config;

    $config->{'field_mappings'} =
      _canonicalize_field_map( $self->bib1_field_map,
        $self->search_field_aliases );
    $config->{'modifier_mappings'} =
      _canonicalize_map( $self->bib1_modifier_map );
    $config->{'filter_mappings'} = _canonicalize_map( $self->bib1_filter_map );
    $config->{'relevance_bumps'} =
      _canonicalize_field_map( $self->bib1_relevance_bump_map );

    if ( $format eq 'json' && can_load( modules => { 'JSON' => undef } ) ) {
        return JSON::to_json($config);
    }
    elsif ( can_load( modules => { 'YAML::Any' => undef } ) ) {
        return YAML::Any::Dump($config);
    }
    return;
}

=head2 initialize

    $QParser->initialize( { 'bib1_field_mappings' => \%bib1_field_mappings,
                            'search_field_alias_mappings' => \%search_field_alias_mappings,
                            'bib1_modifier_mappings' => \%bib1_modifier_mappings,
                            'bib1_filter_mappings' => \%bib1_filter_mappings,
                            'relevance_bumps' => \%relevance_bumps });

Initialize the QueryParser mapping tables based on the provided configuration.
This method was written to play nice with YAML configuration files in the
following format:
=cut

sub initialize {
    my ( $self, $args ) = @_;

    my $field_mappings    = $args->{'field_mappings'};
    my $modifier_mappings = $args->{'modifier_mappings'};
    my $filter_mappings   = $args->{'filter_mappings'};
    my $relbumps          = $args->{'relevance_bumps'};
    my ( $server, $bib1_mapping );
    foreach my $class ( keys %$field_mappings ) {
        foreach my $field ( keys %{ $field_mappings->{$class} } ) {
            if ( $field_mappings->{$class}->{$field}->{'enabled'} ) {
                while ( ( $server, $bib1_mapping ) =
                    each
                    %{ $field_mappings->{$class}->{$field}->{'bib1_mapping'} } )
                {
                    $self->add_bib1_field_map(
                        $class => $field => $server => $bib1_mapping );
                }
                $self->add_search_field_alias( $class => $field =>
                      $field_mappings->{$class}->{$field}->{'index'} );
                foreach my $alias (
                    @{ $field_mappings->{$class}->{$field}->{'aliases'} } )
                {
                    next
                      if ( $alias eq
                        $field_mappings->{$class}->{$field}->{'index'} );
                    $self->add_search_field_alias( $class => $field => $alias );
                }
            }
        }
    }
    foreach my $modifier ( keys %$modifier_mappings ) {
        if ( $modifier_mappings->{$modifier}->{'enabled'} ) {
            while ( ( $server, $bib1_mapping ) =
                each %{ $modifier_mappings->{$modifier}->{'bib1_mapping'} } )
            {
                $self->add_bib1_modifier_map(
                    $modifier => $server => $bib1_mapping );
            }
        }
    }
    foreach my $filter ( keys %$filter_mappings ) {
        if ( $filter_mappings->{$filter}->{'enabled'} ) {
            while ( ( $server, $bib1_mapping ) =
                each %{ $filter_mappings->{$filter}->{'bib1_mapping'} } )
            {
                if ( $filter_mappings->{$filter}->{'target_syntax_callback'} eq
                    'date_filter_target_callback' )
                {
                    $bib1_mapping->{'target_syntax_callback'} =
                      \&QueryParser::PQF::date_filter_target_callback;
                }
                $self->add_bib1_filter_map(
                    $filter => $server => $bib1_mapping );
            }
        }
    }
    foreach my $class ( keys %$relbumps ) {
        foreach my $field ( keys %{ $relbumps->{$class} } ) {
            if ( $relbumps->{$class}->{$field}->{'enabled'} ) {
                while ( ( $server, $bib1_mapping ) =
                    each %{ $relbumps->{$class}->{$field}->{'bib1_mapping'} } )
                {
                    $self->add_relevance_bump(
                        $class => $field => $server => $bib1_mapping,
                        1
                    );
                }
            }
        }
    }
    return $self;
}

sub TEST_SETUP {
    my ($self) = @_;

    require YAML::Any;
    my $config = YAML::Any::LoadFile('/home/jcamins/kohaclone/QueryParser/AutoKohaPQF.yaml');
    $self->initialize($config);
    return $self;
    $self->default_search_class( 'keyword' );

    $self->add_bib1_field_map('keyword' => 'abstract' => 'biblioserver' => { '1' => '62' } );
    $self->add_search_field_alias( 'keyword' => 'abstract' => 'ab' );
    $self->add_bib1_field_map('keyword' => '' => 'biblioserver' => { '1' => '1016' } );
    $self->add_search_field_alias( 'keyword' => '' => 'kw' );
    $self->add_bib1_field_map('author' => '' => 'biblioserver' => { '1' => '1003' } );
    $self->add_search_field_alias( 'author' => '' => 'au' );
    $self->add_bib1_field_map('author' => 'personal' => 'biblioserver' => { '1' => '1004' } );
    $self->add_bib1_field_map('author' => 'corporate' => 'biblioserver' => { '1' => '1005' } );
    $self->add_search_field_alias( 'author' => 'corporate' => 'cpn' );
    $self->add_bib1_field_map('author' => 'conference' => 'biblioserver' => { '1' => '1006' } );
    $self->add_search_field_alias( 'author' => 'conference' => 'cfn' );
    $self->add_bib1_field_map('keyword' => 'local-classification' => 'biblioserver' => { '1' => '20' } );
    $self->add_search_field_alias( 'keyword' => 'local-classification' => 'lcn' );
    $self->add_search_field_alias( 'keyword' => 'local-classification' => 'callnum' );
    $self->add_bib1_field_map('keyword' => 'bib-level' => 'biblioserver' => { '1' => '1021' } );
    $self->add_bib1_field_map('keyword' => 'code-institution' => 'biblioserver' => { '1' => '56' } );
    $self->add_bib1_field_map('keyword' => 'language' => 'biblioserver' => { '1' => '54' } );
    $self->add_search_field_alias( 'keyword' => 'language' => 'ln' );
    $self->add_bib1_field_map('keyword' => 'record-type' => 'biblioserver' => { '1' => '1001' } );
    $self->add_search_field_alias( 'keyword' => 'record-type' => 'rtype' );
    $self->add_search_field_alias( 'keyword' => 'record-type' => 'mc-rtype' );
    $self->add_search_field_alias( 'keyword' => 'record-type' => 'mus' );
    $self->add_bib1_field_map('keyword' => 'content-type' => 'biblioserver' => { '1' => '1034' } );
    $self->add_search_field_alias( 'keyword' => 'content-type' => 'ctype' );
    $self->add_bib1_field_map('keyword' => 'lc-card-number' => 'biblioserver' => { '1' => '9' } );
    $self->add_search_field_alias( 'keyword' => 'lc-card-number' => 'lc-card' );
    $self->add_bib1_field_map('keyword' => 'local-number' => 'biblioserver' => { '1' => '12' } );
    $self->add_search_field_alias( 'keyword' => 'local-number' => 'sn' );
    $self->add_bib1_filter_map( 'biblioserver', 'copydate', { 'target_syntax_callback' => \&QueryParser::PQF::date_filter_target_callback, '1' => '30', '4' => '4' });
    $self->add_bib1_filter_map( 'biblioserver', 'pubdate', { 'target_syntax_callback' => \&QueryParser::PQF::date_filter_target_callback, '1' => 'pubdate', '4' => '4' });
#    $self->add_bib1_field_map('keyword' => 'date-of-publication' => 'biblioserver' => { '1' => 'pubdate' } );
#    $self->add_search_field_alias( 'keyword' => 'date-of-publication' => 'yr' );
#    $self->add_search_field_alias( 'keyword' => 'date-of-publication' => 'pubdate' );
    $self->add_bib1_filter_map( 'biblioserver', 'acqdate', { 'target_syntax_callback' => \&QueryParser::PQF::date_filter_target_callback, '1' => 'Date-of-acquisition', '4' => '4' });
    $self->add_bib1_field_map('keyword' => 'isbn' => 'biblioserver' => { '1' => '7' } );
    $self->add_search_field_alias( 'keyword' => 'isbn' => 'nb' );
    $self->add_bib1_field_map('keyword' => 'issn' => 'biblioserver' => { '1' => '8' } );
    $self->add_search_field_alias( 'keyword' => 'issn' => 'ns' );
    $self->add_bib1_field_map('keyword' => 'identifier-standard' => 'biblioserver' => { '1' => '1007' } );
    $self->add_search_field_alias( 'keyword' => 'identifier-standard' => 'ident' );
    $self->add_bib1_field_map('keyword' => 'upc' => 'biblioserver' => { '1' => 'UPC' } );
    $self->add_search_field_alias( 'keyword' => 'upc' => 'upc' );
    $self->add_bib1_field_map('keyword' => 'ean' => 'biblioserver' => { '1' => 'EAN' } );
    $self->add_search_field_alias( 'keyword' => 'ean' => 'ean' );
    $self->add_bib1_field_map('keyword' => 'music' => 'biblioserver' => { '1' => 'Music-number' } );
    $self->add_search_field_alias( 'keyword' => 'music' => 'music' );
    $self->add_bib1_field_map('keyword' => 'stock-number' => 'biblioserver' => { '1' => '1028' } );
    $self->add_search_field_alias( 'keyword' => 'stock-number' => 'stock-number' );
    $self->add_bib1_field_map('keyword' => 'material-type' => 'biblioserver' => { '1' => '1031' } );
    $self->add_search_field_alias( 'keyword' => 'material-type' => 'material-type' );
    $self->add_bib1_field_map('keyword' => 'place-publication' => 'biblioserver' => { '1' => '59' } );
    $self->add_search_field_alias( 'keyword' => 'place-publication' => 'pl' );
    $self->add_bib1_field_map('keyword' => 'personal-name' => 'biblioserver' => { '1' => 'Personal-name' } );
    $self->add_search_field_alias( 'keyword' => 'personal-name' => 'pn' );
    $self->add_bib1_field_map('keyword' => 'publisher' => 'biblioserver' => { '1' => '1018' } );
    $self->add_search_field_alias( 'keyword' => 'publisher' => 'pb' );
    $self->add_bib1_field_map('keyword' => 'note' => 'biblioserver' => { '1' => '63' } );
    $self->add_search_field_alias( 'keyword' => 'note' => 'nt' );
    $self->add_bib1_field_map('keyword' => 'record-control-number' => 'biblioserver' => { '1' => '1045' } );
    $self->add_search_field_alias( 'keyword' => 'record-control-number' => 'rcn' );
    $self->add_bib1_field_map('subject' => '' => 'biblioserver' => { '1' => '21' } );
    $self->add_search_field_alias( 'subject' => '' => 'su' );
    $self->add_search_field_alias( 'subject' => '' => 'su-to' );
    $self->add_search_field_alias( 'subject' => '' => 'su-geo' );
    $self->add_search_field_alias( 'subject' => '' => 'su-ut' );
    $self->add_bib1_field_map('subject' => 'name-personal' => 'biblioserver' => { '1' => '1009' } );
    $self->add_search_field_alias( 'subject' => 'name-personal' => 'su-na' );
    $self->add_bib1_field_map('title' => '' => 'biblioserver' => { '1' => '4' } );
    $self->add_search_field_alias( 'title' => '' => 'ti' );
    $self->add_bib1_field_map('title' => 'cover' => 'biblioserver' => { '1' => '36' } );
    $self->add_search_field_alias( 'title' => 'cover' => 'title-cover' );
    $self->add_bib1_field_map('keyword' => 'host-item' => 'biblioserver' => { '1' => '1033' } );
    $self->add_bib1_field_map('keyword' => 'video-mt' => 'biblioserver' => { '1' => 'Video-mt' } );
    $self->add_bib1_field_map('keyword' => 'graphics-type' => 'biblioserver' => { '1' => 'Graphic-type' } );
    $self->add_bib1_field_map('keyword' => 'graphics-support' => 'biblioserver' => { '1' => 'Graphic-support' } );
    $self->add_bib1_field_map('keyword' => 'type-of-serial' => 'biblioserver' => { '1' => 'Type-Of-Serial' } );
    $self->add_bib1_field_map('keyword' => 'regularity-code' => 'biblioserver' => { '1' => 'Regularity-code' } );
    $self->add_bib1_field_map('keyword' => 'material-type' => 'biblioserver' => { '1' => 'Material-type' } );
    $self->add_bib1_field_map('keyword' => 'literature-code' => 'biblioserver' => { '1' => 'Literature-Code' } );
    $self->add_bib1_field_map('keyword' => 'biography-code' => 'biblioserver' => { '1' => 'Biography-code' } );
    $self->add_bib1_field_map('keyword' => 'illustration-code' => 'biblioserver' => { '1' => 'Illustration-code' } );
    $self->add_bib1_field_map('title' => 'series' => 'biblioserver' => { '1' => '5' } );
    $self->add_search_field_alias( 'title' => 'series' => 'title-series' );
    $self->add_search_field_alias( 'title' => 'series' => 'se' );
    $self->add_bib1_field_map('title' => 'uniform' => 'biblioserver' => { '1' => 'Title-uniform' } );
    $self->add_search_field_alias( 'title' => 'uniform' => 'title-uniform' );
    $self->add_bib1_field_map('subject' => 'authority-number' => 'biblioserver' => { '1' => 'Koha-Auth-Number' } );
    $self->add_search_field_alias( 'subject' => 'authority-number' => 'an' );
    $self->add_bib1_field_map('keyword' => 'control-number' => 'biblioserver' => { '1' => '9001' } );
    $self->add_bib1_field_map('keyword' => 'biblionumber' => 'biblioserver' => { '1' => '9002', '5' => '100' } );
    $self->add_bib1_field_map('keyword' => 'totalissues' => 'biblioserver' => { '1' => '9003' } );
    $self->add_bib1_field_map('keyword' => 'cn-bib-source' => 'biblioserver' => { '1' => '9004' } );
    $self->add_bib1_field_map('keyword' => 'cn-bib-sort' => 'biblioserver' => { '1' => '9005' } );
    $self->add_bib1_field_map('keyword' => 'itemtype' => 'biblioserver' => { '1' => '9006' } );
    $self->add_search_field_alias( 'keyword' => 'itemtype' => 'mc-itemtype' );
    $self->add_bib1_field_map('keyword' => 'cn-class' => 'biblioserver' => { '1' => '9007' } );
    $self->add_bib1_field_map('keyword' => 'cn-item' => 'biblioserver' => { '1' => '9008' } );
    $self->add_bib1_field_map('keyword' => 'cn-prefix' => 'biblioserver' => { '1' => '9009' } );
    $self->add_bib1_field_map('keyword' => 'cn-suffix' => 'biblioserver' => { '1' => '9010' } );
    $self->add_bib1_field_map('keyword' => 'suppress' => 'biblioserver' => { '1' => '9011' } );
    $self->add_bib1_field_map('keyword' => 'id-other' => 'biblioserver' => { '1' => '9012' } );
    $self->add_bib1_field_map('keyword' => 'date-entered-on-file' => 'biblioserver' => { '1' => 'date-entered-on-file' } );
    $self->add_bib1_field_map('keyword' => 'extent' => 'biblioserver' => { '1' => 'Extent' } );
    $self->add_bib1_field_map('keyword' => 'llength' => 'biblioserver' => { '1' => 'llength' } );
    $self->add_bib1_field_map('keyword' => 'summary' => 'biblioserver' => { '1' => 'Summary' } );
    $self->add_bib1_field_map('keyword' => 'withdrawn' => 'biblioserver' => { '1' => '8001' } );
    $self->add_bib1_field_map('keyword' => 'lost' => 'biblioserver' => { '1' => '8002' } );
    $self->add_bib1_field_map('keyword' => 'classification-source' => 'biblioserver' => { '1' => '8003' } );
    $self->add_bib1_field_map('keyword' => 'materials-specified' => 'biblioserver' => { '1' => '8004' } );
    $self->add_bib1_field_map('keyword' => 'damaged' => 'biblioserver' => { '1' => '8005' } );
    $self->add_bib1_field_map('keyword' => 'restricted' => 'biblioserver' => { '1' => '8006' } );
    $self->add_bib1_field_map('keyword' => 'cn-sort' => 'biblioserver' => { '1' => '8007' } );
    $self->add_bib1_field_map('keyword' => 'notforloan' => 'biblioserver' => { '1' => '8008', '4' => '109' } );
    $self->add_bib1_field_map('keyword' => 'ccode' => 'biblioserver' => { '1' => '8009' } );
    $self->add_search_field_alias( 'keyword' => 'ccode' => 'mc-ccode' );
    $self->add_bib1_field_map('keyword' => 'itemnumber' => 'biblioserver' => { '1' => '8010' } );
    $self->add_bib1_field_map('keyword' => 'homebranch' => 'biblioserver' => { '1' => 'homebranch' } );
    $self->add_search_field_alias( 'keyword' => 'homebranch' => 'branch' );
    $self->add_bib1_field_map('keyword' => 'holdingbranch' => 'biblioserver' => { '1' => '8012' } );
    $self->add_bib1_field_map('keyword' => 'location' => 'biblioserver' => { '1' => '8013' } );
    $self->add_search_field_alias( 'keyword' => 'location' => 'mc-loc' );
    $self->add_bib1_field_map('keyword' => 'acqsource' => 'biblioserver' => { '1' => '8015' } );
    $self->add_bib1_field_map('keyword' => 'coded-location-qualifier' => 'biblioserver' => { '1' => '8016' } );
    $self->add_bib1_field_map('keyword' => 'price' => 'biblioserver' => { '1' => '8017' } );
    $self->add_bib1_field_map('keyword' => 'stocknumber' => 'biblioserver' => { '1' => '1062' } );
    $self->add_search_field_alias( 'keyword' => 'stocknumber' => 'inv' );
    $self->add_bib1_field_map('keyword' => 'stack' => 'biblioserver' => { '1' => '8018' } );
    $self->add_bib1_field_map('keyword' => 'issues' => 'biblioserver' => { '1' => '8019' } );
    $self->add_bib1_field_map('keyword' => 'renewals' => 'biblioserver' => { '1' => '8020' } );
    $self->add_bib1_field_map('keyword' => 'reserves' => 'biblioserver' => { '1' => '8021' } );
    $self->add_bib1_field_map('keyword' => 'local-classification' => 'biblioserver' => { '1' => '8022' } );
    $self->add_bib1_field_map('keyword' => 'barcode' => 'biblioserver' => { '1' => '8023' } );
    $self->add_search_field_alias( 'keyword' => 'barcode' => 'bc' );
    $self->add_bib1_field_map('keyword' => 'onloan' => 'biblioserver' => { '1' => '8024' } );
    $self->add_bib1_field_map('keyword' => 'datelastseen' => 'biblioserver' => { '1' => '8025' } );
    $self->add_bib1_field_map('keyword' => 'datelastborrowed' => 'biblioserver' => { '1' => '8026' } );
    $self->add_bib1_field_map('keyword' => 'copynumber' => 'biblioserver' => { '1' => '8027' } );
    $self->add_bib1_field_map('keyword' => 'uri' => 'biblioserver' => { '1' => '8028' } );
    $self->add_bib1_field_map('keyword' => 'replacementprice' => 'biblioserver' => { '1' => '8029' } );
    $self->add_bib1_field_map('keyword' => 'replacementpricedate' => 'biblioserver' => { '1' => '8030' } );
    $self->add_bib1_field_map('keyword' => 'itype' => 'biblioserver' => { '1' => '8031' } );
    $self->add_search_field_alias( 'keyword' => 'itype' => 'mc-itype' );
    $self->add_bib1_field_map('keyword' => 'ff8-22' => 'biblioserver' => { '1' => '8822' } );
    $self->add_bib1_field_map('keyword' => 'ff8-23' => 'biblioserver' => { '1' => '8823' } );
    $self->add_bib1_field_map('keyword' => 'ff8-34' => 'biblioserver' => { '1' => '8834' } );
# Audience
    $self->add_bib1_field_map('keyword' => 'audience' => 'biblioserver' => { '1' => '8822' } );
    $self->add_search_field_alias( 'keyword' => 'audience' => 'aud' );

# Content and Literary form
    $self->add_bib1_field_map('keyword' => 'fiction' => 'biblioserver' => { '1' => '8833' } );
    $self->add_search_field_alias( 'keyword' => 'fiction' => 'fic' );
    $self->add_bib1_field_map('keyword' => 'biography' => 'biblioserver' => { '1' => '8834' } );
    $self->add_search_field_alias( 'keyword' => 'biography' => 'bio' );

# Format
    $self->add_bib1_field_map('keyword' => 'format' => 'biblioserver' => { '1' => '8823' } );
# format used as a limit FIXME: needed?
    $self->add_bib1_field_map('keyword' => 'l-format' => 'biblioserver' => { '1' => '8703' } );

    $self->add_bib1_field_map('keyword' => 'illustration-code' => 'biblioserver' => { '1' => 'Illustration-code ' } );

# Lexile Number
    $self->add_bib1_field_map('keyword' => 'lex' => 'biblioserver' => { '1' => '9903 r=r' } );

#Accelerated Reader Level
    $self->add_bib1_field_map('keyword' => 'arl' => 'biblioserver' => { '1' => '9904 r=r' } );

#Accelerated Reader Point
    $self->add_bib1_field_map('keyword' => 'arp' => 'biblioserver' => { '1' => '9013 r=r' } );

# Curriculum
    $self->add_bib1_field_map('keyword' => 'curriculum' => 'biblioserver' => { '1' => '9658' } );

## Statuses
    $self->add_bib1_field_map('keyword' => 'popularity' => 'biblioserver' => { '1' => 'issues' } );

## Type Limits
    $self->add_bib1_field_map('keyword' => 'dt-bks' => 'biblioserver' => { '1' => '8700' } );
    $self->add_bib1_field_map('keyword' => 'dt-vis' => 'biblioserver' => { '1' => '8700' } );
    $self->add_bib1_field_map('keyword' => 'dt-sr' => 'biblioserver' => { '1' => '8700' } );
    $self->add_bib1_field_map('keyword' => 'dt-cf' => 'biblioserver' => { '1' => '8700' } );
    $self->add_bib1_field_map('keyword' => 'dt-map' => 'biblioserver' => { '1' => '8700' } );

    $self->add_bib1_field_map('keyword' => 'name' => 'biblioserver' => { '1' => '1002' } );
    $self->add_bib1_field_map('keyword' => 'item' => 'biblioserver' => { '1' => '9520' } );
    $self->add_bib1_field_map('keyword' => 'host-item-number' => 'biblioserver' => { '1' => '8911' } );
    $self->add_search_field_alias( 'keyword' => 'host-item-number' => 'hi' );

    $self->add_bib1_field_map('keyword' => 'alwaysmatch' => 'biblioserver' => { '1' => '_ALLRECORDS', '2' => '103' } );
    $self->add_bib1_field_map('subject' => 'complete' => 'biblioserver' => { '1' => '21', '3' => '1', '4' => '1', '5' => '100', '6' => '3' } );

    $self->add_bib1_modifier_map('relevance' => 'biblioserver' => { '2' => '102' } );
    $self->add_bib1_modifier_map('title-sort-za' => 'biblioserver' => { '7' => '2', '1' => '36', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('title-sort-az' => 'biblioserver' => { '7' => '1', '1' => '36', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('relevance_dsc' => 'biblioserver' => { '2' => '102' } );
    $self->add_bib1_modifier_map('title_dsc' => 'biblioserver' => { '7' => '2', '1' => '4', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('title_asc' => 'biblioserver' => { '7' => '1', '1' => '4', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('author_asc' => 'biblioserver' => { '7' => '2', '1' => '1003', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('author_dsc' => 'biblioserver' => { '7' => '1', '1' => '1003', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('popularity_asc' => 'biblioserver' => { '7' => '2', '1' => '9003', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('popularity_dsc' => 'biblioserver' => { '7' => '1', '1' => '9003', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('call_number_asc' => 'biblioserver' => { '7' => '2', '1' => '8007', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('call_number_dsc' => 'biblioserver' => { '7' => '1', '1' => '8007', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('pubdate_asc' => 'biblioserver' => { '7' => '2', '1' => '31', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('pubdate_dsc' => 'biblioserver' => { '7' => '1', '1' => '31', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('acqdate_asc' => 'biblioserver' => { '7' => '2', '1' => '32', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('acqdate_dsc' => 'biblioserver' => { '7' => '1', '1' => '32', '' => '0', 'op' => '@or' } );

    $self->add_bib1_modifier_map('title_za' => 'biblioserver' => { '7' => '2', '1' => '4', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('title_az' => 'biblioserver' => { '7' => '1', '1' => '4', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('author_za' => 'biblioserver' => { '7' => '2', '1' => '1003', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('author_az' => 'biblioserver' => { '7' => '1', '1' => '1003', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('ascending' => 'biblioserver' => { '7' => '1' } );
    $self->add_bib1_modifier_map('descending' => 'biblioserver' => { '7' => '2' } );

    $self->add_bib1_field_map('title' => 'exacttitle' => 'biblioserver' => { '1' => '4', '4' => '1', '6' => '3' } );
    $self->add_search_field_alias( 'title' => 'exacttitle' => 'ti,ext' );
    $self->add_bib1_field_map('author' => 'exactauthor' => 'biblioserver' => { '1' => '1003', '4' => '1', '6' => '3' } );
    $self->add_search_field_alias( 'author' => 'exactauthor' => 'au,ext' );
    #$self->add_bib1_field_map('keyword' => 'titlekw' => 'biblioserver' => { '1' => '4' } );
    #$self->add_relevance_bump( 'biblioserver' => 'keyword' => 'publisher' => 34, 1 );
    #$self->add_relevance_bump( 'biblioserver' => 'keyword' => 'titlekw' => 14, 1 );

    $self->add_bib1_field_map('subject' => 'headingmain' => 'authorityserver' => { '1' => 'Heading-Main' } );
    $self->add_bib1_field_map('subject' => 'heading' => 'authorityserver' => { '1' => 'Heading' } );
    $self->add_bib1_field_map('subject' => 'matchheading' => 'authorityserver' => { '1' => 'Match-heading' } );
    $self->add_bib1_field_map('subject' => 'seefrom' => 'authorityserver' => { '1' => 'Match-heading-see-from' } );
    $self->add_bib1_field_map('subject' => '' => 'authorityserver' => { '1' => 'Match-heading' } );
    $self->add_bib1_field_map('keyword' => 'alwaysmatch' => 'authorityserver' => { '1' => '_ALLRECORDS', '2' => '103' } );
    $self->add_bib1_field_map('keyword' => 'match' => 'authorityserver' => { '1' => 'Match' } );
    $self->add_bib1_field_map('keyword' => 'thesaurus' => 'authorityserver' => { '1' => 'Subject-heading-thesaurus' } );
    $self->add_bib1_field_map('keyword' => 'authtype' => 'authorityserver' => { '1' => 'authtype', '5' => '100' } );
    $self->add_bib1_field_map('keyword' => '' => 'authorityserver' => { '1' => 'Any' } );
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

    $self->add_bib1_field_map('subject' => 'start' => 'authorityserver' => { '3' => '2', '4' => '1', '5' => '1' } );
    $self->add_bib1_field_map('subject' => 'exact' => 'authorityserver' => { '4' => '1', '5' => '100', '6' => '3' } );

    $self->add_bib1_modifier_map('HeadingAsc' => 'authorityserver' => { '7' => '1', '1' => 'Heading', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('HeadingDsc' => 'authorityserver' => { '7' => '2', '1' => 'Heading', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('AuthidAsc' => 'authorityserver' => { '7' => '1', '1' => 'Local-Number', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('AuthidDsc' => 'authorityserver' => { '7' => '2', '1' => 'Local-Number', '' => '0', 'op' => '@or' } );
    $self->add_bib1_modifier_map('Relevance' => 'authorityserver' => { '2' => '102' } );

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
    $node_count = ($node_count ? '1' : '0');
    for my $node ( @{$self->filters} ) {
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
    return ($self->negate ? '@not @attr 1=_ALLRECORDS @attr 2=103 "" ' : '') . $pqf;
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
    my $attributes = $self->plan->QueryParser->bib1_mapping_by_name( 'filter', $server, $self->name );

    if ($attributes->{'target_syntax_callback'}) {
        return $attributes->{'target_syntax_callback'}->($self->plan->QueryParser, $self->name, $self->args, $self->negate, $server);
    } else {
        return '';
    }
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

    my $attributes = $query_plan->QueryParser->bib1_mapping_by_name('modifier', $server, $self->name);
    $pqf = ($attributes->{'op'} ? $attributes->{'op'} . ' ' : '') . ($self->negate ? '@not @attr 1=_ALLRECORDS @attr 2=103 "" ' : '') . $attributes->{'attr_string'};
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
    my $fieldobj;
    my $relbump;

    if (scalar(@{$self->fields})) {
        foreach my $field (@{$self->fields}) {
            $fieldobj = $self->plan->QueryParser->bib1_mapping_by_name('field', $server, $self->classname, $field);
            $relbump = $self->plan->QueryParser->bib1_mapping_by_name('relevance_bump', $server, $self->classname, $field);
            if ($relbump) {
                $fieldobj->{'attr_string'} .= ' ' . $relbump->{'attr_string'};
            }
            push @fields, $fieldobj;
        }
    } else {
        $fieldobj = $self->plan->QueryParser->bib1_mapping_by_name('field', $server, $self->classname, '');
        my $relbumps = $self->plan->QueryParser->bib1_mapping_by_name('relevance_bump', $server, $self->classname, '');
        push @fields, $fieldobj;
        if ($relbumps) {
            foreach my $field (keys %$relbumps) {
                $relbump = $relbumps->{$field};
                $fieldobj = $self->plan->QueryParser->bib1_mapping_by_name('field', $server, $relbump->{'classname'}, $relbump->{'field'});
                $fieldobj->{'attr_string'} .= ' ' . $relbump->{'attr_string'};
                push @fields, $fieldobj;
            }
        }
    }

    if (@{$self->phrases}) {
        foreach my $phrase (@{$self->phrases}) {
            if ($phrase) {
                $pqf .= ' @or ' x (scalar(@fields) - 1);
                foreach my $attributes (@fields) {
                    $pqf .= $attributes->{'attr_string'} . ($attributes->{'4'} ? '' : ' @attr 4=1') . ' "' . $phrase . '" ';
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
    return ($self->negate ? '@not @attr 1=_ALLRECORDS @attr 2=103 "" ' : '') . $pqf;
}

package QueryParser::PQF::_util;
use Scalar::Util qw(looks_like_number);

sub attributes_to_attr_string {
    my ($attributes) = @_;
    my $attr_string = '';
    my $key;
    my $value;
    while (($key, $value) = each(%$attributes)) {
        next unless looks_like_number($key);
        $attr_string .= ' @attr ' . $key . '=' . $value . ' ';
    }
    $attr_string =~ s/^\s*//;
    $attr_string =~ s/\s*$//;
    $attr_string .= ' ' . $attributes->{''} if defined $attributes->{''};
    return $attr_string;
}

1;
