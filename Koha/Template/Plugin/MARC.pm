package Koha::Template::Plugin::MARC;

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

=head1 NAME

Koha::Template::Plugin::MARC - Template::Toolkit to make MARC friendly

=head1 SYNOPSIS

[% USE record = MARC(mymarc) %] <!-- translate MARC::Record to T::T hash -->
<h1>[% record.f245.sa %]</h1> <!-- subfield 245$a -->
[% record.f245.all %] <!-- all subfields concatenated together -->
[% FOREACH link IN record.f856s %] <!-- process each 856 field -->
    <a href="whatever/[% link.su %]">[% link.sy %]</a> <!-- create a link on 856$y -->
[% END %] <!-- /FOREACH link IN record.856s -->
[% FOREACH contents IN record.f505s %] <!-- process each 505 field -->
    [% FOREACH subf IN contents.subfields %] <!-- process each subfield -->
        [% SWITCH subf.code %]
        [% CASE 'a' %]
            <span class='contents'>[% subf.value %]</span>
        [% CASE 't' %]
            <span class='title'>[% subf.value %]</span>
        [% CASE 'r' %]
            <span class='responsibility'>[% subf.value %]</span>
        [% END %]
    [% END %] <!-- /FOREACH contents.subfields -->
[% END %] <!-- /FOREACH contents IN record.f505s -->
[% FOREACH subj IN record.f6xxs %]
    <a href="whatever/[% subj.s9 %]">[% subj.sa %]</a> <!-- create a link on 6[0-9]{2}$a -->
[% END %]
[% FOREACH field IN record.fields %]
    [% SWITCH field.tag %]
    [% CASE '600' %]
        Subject: [% field.all %] is what we are all about
    [% CASE '700' %]
        Co-author: [% field.all %], I presume?
    [% END %]
[% END %]

=head1 DESCRIPTION

A Template::Toolkit plugin which given a MARC::Record object parses it into a
hash that can be accessed directly in Template::Toolkit.

=head1 ACCESSORS

By using some clever AUTOLOAD acrobatics, this plugin offers the user six
types of accessors.

=head2 Direct accessors

    [% record.f245.sa %]
    
    print $record->f245->sa;

By prefixing field numbers with an 'f' and subfield codes with an 's', the first
field/subfield with a given tag/code can be accessed.

=head2 Concatenated accessors

    [% record.f245.all %]
    
    print $record->f245->all;

A string consisting of all subfields concatenated together is accessible through
the all member of field objects.

=head2 Subfield iterators

    [% FOREACH subfield IN record.f245.subfields %]
        [% subfield.code %] = [% subfield.value %]
    [% END %]

    foreach my $subfield ($record->f245) {
        print $subfield->code, ' = ', $subfield->value;
    }

Subfield iterators are accessible through the subfields member of field objects.

=head2 Field iterators

    [% FOREACH field IN record.f500s %]
        [% field.all %]
    [% END %]

    foreach my $field ($record->f500s) {
        print $field->all;
    }

Field iterators are accessible by adding an 's' to the end of field names:
f500s, etc.

=head2 Section iterators

    [% FOREACH field IN record.f5xxs %]
        [% field.all %]
    [% END %]

    foreach my $field ($record->f5xxs) {
        print $field->all;
    }

All the fields in a section (identified by the first digit of the tag) can
be accessed with 'fNxxs' and then iterated through.

=head2 Complete field list

    [% FOREACH field IN record.fields %]
        [% field.all %]
    [% END %]

    foreach my $field ($record->fields) {
        print $field->all;
    }

All the fields in a record can be accessed via the fields object method.

=head1 WHAT THIS PLUGIN DOES NOT DO

This plugin will not sanity-check your code to make sure that you are accessing
fields and subfields with proper allowances for repetition. If you access a value
using [% record.f505.st %] it is presumed that was intentional, and there will be
no warning or error of any sort.

However, the flip-side of this is that this plugin will not dictate your code
style. You can access the data using direct (non-repeatable) accessors, by
iterating over subfields, by iterating over subfields of a specific tag, by
iterating over fields in a particular block (0xx, 1xx, 2xx, etc.), or by
iterating over all fields.

=cut

use Modern::Perl;
use MARC::Record;
use MARC::Field;

use Template::Plugin;
use base qw( Template::Plugin );

our $AUTOLOAD;

=head1 METHODS

=head2 load

Used by Template::Toolkit for loading this plugin.

=cut

sub load {
    my ($class, $context) = @_;
    return $class;
}

=head2 new

Instantiates a new object for the given MARC::Record. Can be called
using any of the following declarations:

    [% USE MARC(mymarc) %]
    [% USE marc(mymarc) %]
    [% USE MARC mymarc %]
    [% USE MARC(marc=mymarc) %]
    [% USE MARC marc=mymarc %]

When run from Perl, the object can be created with either of the following
two calling conventions:

    $record = Koha::Template::Plugin::MARC->new({}, $marc, [\%config]);
    $record = Koha::Template::Plugin::MARC->new([$context], { marc => $marc });

The $context hashref passed as the first argument is mandatory when using
positional parameters and optional when using named parameters.

=cut

sub new {
    my $config = ref($_[-1]) eq 'HASH' ? pop(@_) : { };
    my ($class, $context, $marc) = @_;

    # marc can be a positional or named argument
    $marc = $config->{'marc'} unless defined $marc;

    bless { 
        %$config,
            marc => $marc,
    }, $class;
}

=head2 init

Initializes the MARC object. This is called only on the first access attempt
on the object, to avoid unnecessary processing.

=cut

sub init {
    my $self = shift;
    return $self if $self->{'record'};

    my $recordhash = { fields => [] };

    foreach my $field ($self->{'marc'}->fields()) {
        my $fieldobj = Koha::Template::Plugin::MARC::Field->new($field);
        my $tag = $fieldobj->tag();
        my $section = 'f' . substr($tag, 0, 1) . 'xxs';
        $recordhash->{"f$tag"} = $fieldobj unless $recordhash->{"f$tag"};
        $recordhash->{"f$tag" . 's'} = [] unless $recordhash->{"f$tag" . 's'};
        push @{$recordhash->{"f$tag" . 's'}}, $fieldobj;
        $recordhash->{"$section"} = [] unless $recordhash->{"$section"};
        push @{$recordhash->{"$section"}}, $fieldobj;
        push @{$recordhash->{'fields'}}, $fieldobj;
    }

    $self->{'record'} = $recordhash;
    return $self;
}

=head2 filter

    $record->filter({ '4' => 'edt' })->[0]->sa

    [% record.filter('4'='edt').0.sa

Filters a set of fields according to the specified criteria

=cut

sub filter {
    my ($self, $selectors) = @_;

    $self->init();

    my $fields = $self->{'record'}->{'fields'};
    foreach my $selector (keys %$selectors) {
        my $possibilities = [];
        foreach my $testfield (@$fields) {
            push @$possibilities, $testfield if $testfield->has($selector, $selectors->{$selector});
        }
        $fields = $possibilities;
    }

    return $fields;
}

=head2 marc

Returns the MARC::Record object associated with the instance.

=cut

sub marc {
    my $self = shift;
    return $self->{'marc'};
}

sub AUTOLOAD {
    my $self = shift;
    (my $a = $AUTOLOAD) =~ s/.*:://;

    $self->init;
    
    return $self->{'record'}->{"$a"};
}

1;

=head1 HELPER CLASSES

=cut

package Koha::Template::Plugin::MARC::Field;

=head2 Koha::Template::Plugin::MARC::Field

Object class to allow nested auto-loading. Not used directly.

=cut

use Modern::Perl;
use MARC::Field;

our $AUTOLOAD;

sub new {
    my ($class, $field) = @_;
    my $fieldhash = {
        'tag' => $field->tag(),
        'subfields' => [],
    };
    if ($field->is_control_field()) {
        $fieldhash->{'value'} = $field->data();
            push @{$fieldhash->{'subfields'}}, Koha::Template::Plugin::MARC::Subfield->new('@' => $field->data());
    } else {
        $fieldhash->{'ind1'} = $field->indicator(1);
        $fieldhash->{'ind2'} = $field->indicator(2);
        my @subfields = $field->subfields();
        foreach my $subf (@subfields) {
            $fieldhash->{"s$subf->[0]"} = $subf->[1] unless $fieldhash->{"s$subf->[0]"};
            $fieldhash->{'all'} .= ' ' if $fieldhash->{'all'};
            $fieldhash->{'all'} .= $subf->[1];
            push @{$fieldhash->{'subfields'}}, Koha::Template::Plugin::MARC::Subfield->new($subf->[0] => $subf->[1]);
        }
    }

    bless $fieldhash, $class;
}

sub has {
    my ($self, $selector, $match) = @_;

    unless ($selector eq 'ind1' || $selector eq 'ind2' || $selector eq 'tag') {
        $selector = "s$selector"; # Everything else is a subfield
    }

    return $self->{$selector} eq $match if (defined $self->{$selector} && defined $match);
    return defined $self->{$selector};
}

sub filter {
    my ($self, $selectors) = @_;

    my $result = '';
    foreach my $selector (keys %$selectors) {
        if ($selector eq 'code') {
            foreach my $subf (@{$self->{'subfields'}}) {
                if (index($selectors->{$selector}, $subf->code) >= 0) {
                    $result .= ' ' if $result;
                    $result .= $subf->value;
                }
            }
        }
    }
    return $result;
}

sub AUTOLOAD {
    my $self = shift;
    (my $a = $AUTOLOAD) =~ s/.*:://;

    return $self->{"$a"};
}

1;

package Koha::Template::Plugin::MARC::Subfield;

=head2 Koha::Template::Plugin::MARC::Subfield

Object class to allow nested auto-loading. Not used directly.

=cut


use Modern::Perl;

sub new {
    my ($class, $code, $value) = @_;

    bless {
        code => $code,
        value => $value,
    }, $class;
}

sub code {
    my $self = shift;
    return $self->{'code'};
}

sub value {
    my $self = shift;
    return $self->{'value'};
}

=head1 AUTHOR

Jared Camins-Esakov, C & P Bibliography Services <jcamins@cpbibliography.com>

=cut

1;
