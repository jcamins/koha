package Koha::SearchEngine::Zebra;
# Parts Copyright 2012 BibLibre
# Copyright 2013 C & P Bibliography Services
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# Koha; if not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307 USA

use Modern::Perl;
use ZOOM;

# We are not quite ready to use a unified Moose API for this yet, but we'll keep
# the code until such as time as we are ready to use it.
#use Moose;
#
#extends 'Data::SearchEngine::Zebra';
#
# the configuration file is retrieved from KOHA_CONF by default, provide it from there²
#has '+conf_file' => (
#    is => 'ro',
#    isa => 'Str',
#    default =>  $ENV{KOHA_CONF},
#    required => 1
#);

=head1 NAME

Koha::SearchEngine::Zebra - Koha's interface to the Zebra search engine

=head1 SYNOPSIS

This module handles Koha's direct interface to the Zebra search engine.

=head1 DESCRIPTION


=head1 FUNCTIONS

=cut

=head2 search

=cut

sub search {
    my ( $self, $query, $params ) = @_;

    my @zoom_queries;
    my @zoom_results;

    my @servers = map { $self->server($_) } @{ $params->{'servers'} };
    my $results;

    $self->_ZOOM_event_loop(
        \@servers,
        \@zoom_results,
        sub {
            my ( $i, $size ) = @_;
            my $first_record = defined($params->{'offset'}) ? $params->{'offset'} + 1 : 1;
            my $hits = $zoom_results[ $i - 1 ]->size();
            $results->{'count'} += $hits;
            my $last_record = $hits;
            if ( defined $params->{'max_results'} && $params->{'offset'} + $params->{'max_results'} < $hits ) {
                $last_record = $params->{'offset'} + $params->{'max_results'};
            }

            for my $j ( $first_record .. $last_record ) {
                my $record =
                  $zoom_results[ $i - 1 ]->record( $j - 1 )->raw();    # 0 indexed
                my $item = {
                    'record' => $record,
                    'index'  => $j,
                    'server' => $params->{'servers'}->{$i}
                };
                push @{ $results->{'items'} }, $item;
            }
        }
    );
    foreach my $zoom_query (@zoom_queries) {
        $zoom_query->destroy();
    }
}

=head2 _ZOOM_event_loop

    _ZOOM_event_loop(\@zconns, \@results, sub {
        my ( $i, $size ) = @_;
        ....
    } );

Processes a ZOOM event loop and passes control to a closure for
processing the results, and destroying the resultsets.

=cut

sub _ZOOM_event_loop {
    my ($self, $zconns, $results, $callback) = @_;
    while ( ( my $i = ZOOM::event( $zconns ) ) != 0 ) {
        my $ev = $zconns->[ $i - 1 ]->last_event();
        if ( $ev == ZOOM::Event::ZEND ) {
            next unless $results->[ $i - 1 ];
            my $size = $results->[ $i - 1 ]->size();
            if ( $size > 0 ) {
                $callback->($i, $size);
            }
        }
    }

    foreach my $result (@$results) {
        $result->destroy();
    }
    return;
}


1;
__END__

=head1 AUTHOR

Koha Development Team <http://koha-community.org/>

=cut
