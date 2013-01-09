package Koha::ILL::Transaction;

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

Koha::ILL::Originator - ILL originator object

=head1 SYNOPSIS

ILL request originator class. This class contains all the code necessary
to create and send ILL requests.

=head1 DESCRIPTION

=cut

use strict;
use warnings;

use base qw(Class::Accessor);

sub new {
    my ($class, $args) = shift;

    my $self = $class->SUPER::new($args);

    bless $self, $class;
    return $self;
}

sub GenerateRequest {
    my ($self, $query) = @_;
}

sub CancelRequest {
    my ($self) = @_;
}

sub RequestAccepted {
    my ($self, $args) = @_;
}

sub RequestRefused {
    my ($self, $args) = @_;
}

sub _send_request {
    my ($self, $args) = @_;
}

1;
