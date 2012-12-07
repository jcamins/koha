#!/usr/bin/perl
# Copyright C & P Bibliography Services 2012

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
use MARC::Record;
use Template;
use Test::More tests => 21;

BEGIN {
    use_ok('Koha::Template::Plugin::MARC');
}

my $marc = MARC::Record->new;

$marc->add_fields(
        [ '001', 'abcdefghijklm' ],
        [ '100', '1', ' ', a => 'Carter, Philip J.' ],
        [ '245', '1', '0', a => 'Test your emotional intelligence :',
            b => 'improve your EQ and learn how to impress potential employers.' ],
        [ '505', '0', '0', t => 'What is emotional intelligence?',
            t => 'Why am I in this handbasket?',
            t => 'Where am I going?' ],
        [ '520', ' ', ' ', a => 'A thrilling book about EQ testing.' ],
        [ '650', ' ', '0', a => 'Emotional intelligence.' ],
        [ '650', ' ', '0', a => 'Personality assessment.' ],
        [ '650', ' ', '7', a => 'Self-evaluation.' ],
        [ '700', '1', '7', a => 'Smith, Jim,',
            d => '1900-2000.',
            4 => 'edt',
            9 => '1234' ],
        );

is(Koha::Template::Plugin::MARC->load({ context => 1}), 'Koha::Template::Plugin::MARC', 'load method returns correct class name');

my $record = Koha::Template::Plugin::MARC->new({}, $marc);
is(ref $record, 'Koha::Template::Plugin::MARC', 'Created expected object');
ok(defined $record->marc, 'MARC exists with positional parameters');
$record = Koha::Template::Plugin::MARC->new({ marc => $marc });
ok(defined $record->marc, 'MARC exists with named parameters');
is($record->f001->value, 'abcdefghijklm', 'Accessed control field using direct accessor');
is($record->f245->sa, 'Test your emotional intelligence :', 'Accessed 245$a using direct accessor');
is($record->f245->all, 'Test your emotional intelligence : improve your EQ and learn how to impress potential employers.', 'Got expected result for whole 245 using all accessor');
is($record->f650->sa, 'Emotional intelligence.', 'Retrieved first 650$a as expected using direct accessor');
is(scalar @{$record->f650s}, 3, 'Found three 650s using iterable fields accessor');
my $concat = '';
foreach my $title (@{$record->f505->subfields}) {
    $concat .= $title->value . ' -- ';
}
is($concat, 'What is emotional intelligence? -- Why am I in this handbasket? -- Where am I going? -- ', 'Retrieved 505 using iterable subfields accessor');
is(scalar @{$record->f5xxs}, 2, 'Found two notes using section accessor');
is(scalar @{$record->fields}, 9, 'Found nine fields using fields accessor');

is($record->filter({ '4' => 'edt' })->[0]->sa, 'Smith, Jim,', 'Filtered for editor');
is($record->filter({ 'tag' => '505' })->[0]->tag, '505', 'Filter for 505 field');
is(scalar @{$record->filter({ 'tag' => '650', 'ind2' => '7' })}, 1, 'Filter for 650 field with ind2=7');
is(scalar @{$record->filter({ 'ind1' => ' ' })}, 4, 'Filter for fields with ind1=[space]');
is(scalar @{$record->filter({ '4' })}, 1, 'Filter for any subfield 4 (the error about there being an odd number of elements was intentional)');
is(scalar @{$record->filter({ })}, 9, 'Filtering for nothing returns all fields');

is($record->f700->filter({ 'code' => 'ad' }), 'Smith, Jim, 1900-2000.', 'Filtered for subfields');

my $template = Template->new( { INCLUDE_PATH => '.', PLUGIN_BASE => 'Koha::Template::Plugin'} );

my $example = <<_ENDEXAMPLE_;
[%- USE record = MARC(mymarc) %]
[%- record.f245.sa %] [% record.f245.sb %]
[%- record.f505.all %]
[%- FOREACH subj IN record.f650s %]
    [%- subj.all %]
[%- END %]
[%- FOREACH field IN record.fields %]
    [%- field.tag %]:
    [%- FOREACH subf IN field.subfields %]
        [%- subf.code %] => [% subf.value %]
    [%- END %]
[%- END %]
_ENDEXAMPLE_

# Yes, the expected result is absolute gibberish. Whitespace is nearly
# impossible to troubleshoot, and this test works.
my $expected = <<_ENDEXPECTED_;
Test your emotional intelligence : improve your EQ and learn how to impress potential employers.What is emotional intelligence? Why am I in this handbasket? Where am I going?Emotional intelligence.Personality assessment.Self-evaluation.001:@ => abcdefghijklm100:a => Carter, Philip J.245:a => Test your emotional intelligence :b => improve your EQ and learn how to impress potential employers.505:t => What is emotional intelligence?t => Why am I in this handbasket?t => Where am I going?520:a => A thrilling book about EQ testing.650:a => Emotional intelligence.650:a => Personality assessment.650:a => Self-evaluation.700:a => Smith, Jim,d => 1900-2000.4 => edt9 => 1234
_ENDEXPECTED_

my $output;
$template->process(\$example, { 'mymarc' => $marc }, \$output);
is($output, $expected, 'Processed template for expected results');
