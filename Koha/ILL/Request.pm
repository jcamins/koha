package Koha::ILL::Request;

# Copyright 2013 C & P Bibliography Services
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=head1 NAME

Koha::ILL::Request - class representing an ILL request

=head1 SYNOPSIS

Object-oriented class that encapsulates a single ILL transaction.

=head1 DESCRIPTION

=cut

use strict;
use warnings;

use base qw(Class::Accessor);

__PACKAGE__->mk_accessors(qw( originator_id originator originator_ip handler_id handler handler_ip origination_timestamp query borrowernumber item_level biblionumber itemnumber status ));

sub new {
    my $class = shift;
    my $record = shift;

    my $self = $class->SUPER::new();

    bless $self, $class;
    return $self;
}

1;
