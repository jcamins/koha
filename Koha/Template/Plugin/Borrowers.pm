package Koha::Template::Plugin::Borrowers;

# Copyright ByWater Solutions 2013

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
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use base qw( Template::Plugin );

use Date::Calc qw/Today Add_Delta_YM check_date Date_to_Days/;

use C4::Koha;

=pod

This plugin is a home for various patron related Template Toolkit functions
to help streamline Koha and to move logic from the Perl code into the
Templates when it makes sense to do so.

To use, first, include the line '[% USE Borrowers %]' at the top
of the template to enable the plugin.

For example: [% IF Borrowers.IsDebarred( borrower.borrowernumber ) %]
removes the necessity of setting a template variable in Perl code to
find out if a patron is restricted even if that variable is not evaluated
in any way in the script.

=cut

sub IsDebarred {
    my ( $self, $borrower ) = @_;

    return unless $borrower;

    if ( $borrower->{'debarred'} && check_date( split( /-/, $borrower->{'debarred'} ) ) ) {
        if ( Date_to_Days(Date::Calc::Today) < Date_to_Days( split( /-/, $borrower->{'debarred'} ) ) ) {
            return 1;
        }
    }

    return 0;
}

1;