package OpenILS::QueryParser::Driver::PQF::query_plan::node::atom;
use base 'QueryParser::query_plan::node::atom';

use strict;
use warnings;

=head2 OpenILS::QueryParser::Driver::PQF::query_plan::node::atom::target_syntax

    my $pqf = $atom->target_syntax($server);

Transforms a QueryParser::query_plan::node::atom object into PQF. Do not use
directly.

=cut

sub target_syntax {
    my ($self, $server) = @_;

    return ' "' .  $self->content . '" ';
}

1;