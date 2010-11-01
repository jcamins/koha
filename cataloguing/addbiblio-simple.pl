#!/usr/bin/perl 

# Copyright 2010 C & P Bibliography Services
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
# You should have received a copy of the GNU General Public License along with
# Koha; if not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307 USA

# TODO: hook into the C4 framework
# TODO: make the auth_finder search more than one authority type
# TODO: add ability push data into MARC records
# TODO: add intelligence to parse input based on punctuation, etc.

use warnings;
use strict;
use CGI;
use Template;
use C4::Biblio;
use C4::AuthoritiesMarc;
use MARC::Record;
use C4::Koha;    # XXX subfield_is_koha_internal_p
use C4::Languages qw(getAllLanguages);

my $cgi = CGI->new();
my $biblionumber  = $cgi->param('biblionumber'); # if biblionumber exists, it's a modif, not a new biblio.
my $template = Template->new();
my $record = GetMarcBiblio($biblionumber);
my $frameworkcode = $cgi->param('frameworkcode');
my $op = $cgi->param('op');
my $alllanguages = getAllLanguages();
my $file = 'addbiblio-simple.tt';
my $dbh           = C4::Context->dbh;

my @notes;
my @provenancenotes;
my @bindingnotes;

if ( C4::Context->preference('marcflavour') eq 'UNIMARC' ) {
    MARC::File::XML->default_record_format('UNIMARC');
}

$frameworkcode = &GetFrameworkCode($biblionumber)
  if ( $biblionumber and not($frameworkcode) );

$frameworkcode = '' if ( $frameworkcode eq 'Default' );

if ($biblionumber) {
    $record = GetMarcBiblio($biblionumber);
}

if ($op eq 'addbiblio') {
    if (!$biblionumber) {
        $record = MARC::Record->new();

        if (C4::Context->preference('marcflavour') eq 'UNIMARC') {
            # TODO: implement UNIMARC
        } else {
            $record->leader("     nam a22     7a 4500");
            my @fields;
        }
        my $oldbibitemnum;
        ($biblionumber, $oldbibitemnum) = AddBiblio($record, $frameworkcode);
    } else {
        if ( C4::Context->preference('marcflavour') eq 'UNIMARC' ) {
# TODO: implement UNIMARC
        } else {
            my @fields = $record->field('1..');
            if (@fields) {
                foreach my $field (@fields) {
                    $record->delete_field($field);
                }
            }
            my %tagmapping = ( '100' => '100',
                               '110' => '110', 
                               '111' => '111',
                               '130' => '130' );

            UpdateRecordFromAuthority($record, $frameworkcode, $cgi->param('author_authid'), %tagmapping);
        }

        my ($titleproper, $subtitle, $responsibility) = ParseTitle($cgi->param('title'));
        UpdateRecordWithField($record, $frameworkcode, 'titleproper', $titleproper);
        UpdateRecordWithField($record, $frameworkcode, 'subtitle', $subtitle);
        UpdateRecordWithField($record, $frameworkcode, 'responsibility', $responsibility);
        UpdateRecordWithField($record, $frameworkcode, 'city', $cgi->param('city'));
        UpdateRecordWithField($record, $frameworkcode, 'publisher', $cgi->param('publisher'));
        UpdateRecordWithField($record, $frameworkcode, 'date', $cgi->param('date'));
        UpdateRecordWithField($record, $frameworkcode, 'pagination', $cgi->param('pagination'));
        UpdateRecordWithField($record, $frameworkcode, 'size', $cgi->param('size'));

        UpdateRecordReplacingField($record, $frameworkcode, 'notes', $cgi->param('notesinput'));
        UpdateRecordReplacingField($record, $frameworkcode, 'provenance', $cgi->param('provenanceinput'));
        UpdateRecordReplacingField($record, $frameworkcode, 'binding', $cgi->param('bindinginput'));
        ModBiblio($record, $biblionumber, $frameworkcode);
    }
}

print $cgi->header(-charset=>'utf-8');

SetParam('author_authid', $cgi, $record, $biblionumber);
SetParam('author_name', $cgi, $record, $biblionumber);

SetParam('titleproper', $cgi, $record, $biblionumber);
SetParam('subtitle', $cgi, $record, $biblionumber);
SetParam('responsibility', $cgi, $record, $biblionumber);

SetParam('city', $cgi, $record, $biblionumber);
SetParam('publisher', $cgi, $record, $biblionumber);
SetParam('date', $cgi, $record, $biblionumber);

if (!$cgi->param('language')) {
    $cgi->param('language', 'eng');
}

SetParam('pagination', $cgi, $record, $biblionumber);
SetParam('size', $cgi, $record, $biblionumber);

my $notefields = GetRecordValue('notes', $record, GetFrameworkCode($biblionumber));
foreach my $field (@$notefields) {
    push @notes, $field->{'subfield'};
}
if (scalar @notes == 0) {
    push @notes, '';
}

my $provenancefields = GetRecordValue('provenance', $record, GetFrameworkCode($biblionumber));
foreach my $field (@$provenancefields) {
    push @provenancenotes, $field->{'subfield'};
}
if (scalar @provenancenotes == 0) {
    push @provenancenotes, '';
}

my $bindingfields = GetRecordValue('binding', $record, GetFrameworkCode($biblionumber));
foreach my $field (@$bindingfields) {
    push @bindingnotes, $field->{'subfield'};
}
if (scalar @bindingnotes == 0) {
    push @bindingnotes, '';
}

my $vars = {
    'languages' => $alllanguages,
    'notes' => \@notes,
    'provenance' => \@provenancenotes,
    'binding' => \@bindingnotes,
    $cgi->Vars
};

$template->process($file, $vars) || die "Template process failed: ", $template->error(), "\n";

sub SetParam {
    my ($param, $cgi, $record, $biblionumber) = @_;

    if (!$cgi->param($param)) {
        my $linkref = GetRecordValue($param, $record, GetFrameworkCode($biblionumber));
        $cgi->param($param, $linkref->[0]->{'subfield'});
    }
}

sub UpdateRecordWithField {
    my ($record, $frameworkcode, $mappingname, $value) = @_;
    my $mapping = GetSingleFieldMapping($frameworkcode, $mappingname);
    my $field = $record->field($mapping->{'fieldcode'});
    if (length($value)) {
        $field->update($mapping->{'subfieldcode'} => $value);
    } else {
        $field->delete_subfield(code => $mapping->{'subfieldcode'});
    }
}

sub UpdateRecordReplacingField {
    my ($record, $frameworkcode, $mappingname, @value) = @_;
    my $mapping = GetSingleFieldMapping($frameworkcode, $mappingname);
    my @fields = $record->field($mapping->{'fieldcode'});
    if (@fields) {
        foreach my $field (@fields) {
            $record->delete_field($field);
        }
    }
    foreach my $note (@value) {
        my $field = MARC::Field->new($mapping->{'fieldcode'}, '', '', $mapping->{'subfieldcode'} => $note);
        $record->insert_grouped_field($field);
    }
}

sub UpdateRecordFromAuthority {
    my ($record, $framework, $authid, %tagmapping) = @_;
    my $authrecord = GetAuthority($authid);
    my $authheading;
    my $recordheading;
    if ( C4::Context->preference('marcflavour') eq 'UNIMARC' ) {
        # TODO: implement UNIMARC
    } else {
        $authheading = $authrecord->field('1..');
    }
    $recordheading = MARC::Field->new($tagmapping{$authheading->tag()}, $authheading->indicator(1), $authheading->indicator(2), 'a' => 'xxx');
    foreach my $subfield ($authheading->subfields()) {
        $recordheading->update(@$subfield[0] => @$subfield[1]);
    }
    $recordheading->update('9' => $authid);
    $record->insert_grouped_field($recordheading);
}

sub ParseTitle {
    my ($title) = @_;
    my $titleproper;
    my $subtitle;
    my $responsibility;

    ($titleproper, $subtitle, $responsibility) = $title =~ /^([^:\/]+(?: [:\/]))(?: ([^\/]+(?: [\/])))?(?: (.+))?$/;
    return ($titleproper, $subtitle, $responsibility);
}
