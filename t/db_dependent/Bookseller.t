#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 12;

BEGIN {
    use_ok('C4::Bookseller');
}

my $booksellerid = C4::Bookseller::AddBookseller(
    {
        name     => "my vendor",
        address1 => "bookseller's address",
        phone    => "0123456",
        active   => 1
    },
    [ { name => 'John Smith', phone => '0123456x1' } ]
);

my @booksellers = C4::Bookseller::GetBookSeller('my vendor');
ok(
    (grep { $_->{'id'} == $booksellerid } @booksellers),
    'GetBookSeller returns correct record when passed a name'
);

my $bookseller = C4::Bookseller::GetBookSellerFromId($booksellerid);
is( $bookseller->{'id'}, $booksellerid, 'Retrieved desired record' );
is( $bookseller->{'phone'}, '0123456', 'New bookseller has expected phone' );
is( ref $bookseller->{'contacts'},
    'ARRAY', 'GetBookSellerFromId returns arrayref of contacts' );
is(
    ref $bookseller->{'contacts'}->[0],
    'C4::Bookseller::Contact',
    'First contact is a contact object'
);
is( $bookseller->{'contacts'}->[0]->phone,
    '0123456x1', 'Contact has expected phone number' );

$bookseller->{'name'} = 'your vendor';
$bookseller->{'contacts'}->[0]->phone('654321');
C4::Bookseller::ModBookseller($bookseller);

$bookseller = C4::Bookseller::GetBookSellerFromId($booksellerid);
is( $bookseller->{'name'}, 'your vendor',
    'Successfully changed name of vendor' );
is( $bookseller->{'contacts'}->[0]->phone,
    '654321',
    'Successfully changed contact phone number by modifying bookseller hash' );

C4::Bookseller::ModBookseller( $bookseller,
    [ { name => 'John Jacob Jingleheimer Schmidt' } ] );

$bookseller = C4::Bookseller::GetBookSellerFromId($booksellerid);
is(
    $bookseller->{'contacts'}->[0]->name,
    'John Jacob Jingleheimer Schmidt',
    'Changed name of contact'
);
is( $bookseller->{'contacts'}->[0]->phone,
    undef, 'Removed phone number from contact' );

END {
    C4::Bookseller::DelBookseller($booksellerid);
    is( C4::Bookseller::GetBookSellerFromId($booksellerid),
        undef, 'Bookseller successfully deleted' );
}
