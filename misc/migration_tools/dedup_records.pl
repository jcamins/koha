#!/usr/bin/perl

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
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=head1 NAME

dedup_records.pl - clean up duplicate records

=head1 SYNOPSIS

  dedup_records.pl --match=1 -a

  dedup_records.pl --match="LC-card-number/010a" --select="date" \
    --limit="authid > 367123592" -a

  dedup_records.pl --match="Match/100abcdefghijklmnopqrstuvwxyz" \
    --select="source=DLC" --select="date" --limit="authtypecode='PERSO_NAME'" -a

=head1 DESCRIPTION

This script will identify duplicate records, and either suggest that you
merge them (in the case of bibliographic records) or automatically merge
them for you (in the case of authority records).

=cut

use Modern::Perl;
use Getopt::Long;
use Pod::Usage;
use Time::HiRes qw/time/;
use POSIX qw/strftime ceil/;

use C4::Context;
use C4::Matcher;
use C4::Biblio;
use C4::AuthoritiesMarc;

sub usage {
    pod2usage( -verbose => 2 );
    exit;
}

=head1 OPTIONS

=over 8

=item B<--help>

Prints this help

=item B<-v|--verbose>

Print verbose log information (warning: very verbose!).

=item B<-t|--test>

Do not actually make any changes to the database, just report what changes
would be made.

=item B<-r|--report>

Print a report of what happened during the run.

=item B<-l|--limit=S>

Only process those records that match the user-specified WHERE clause
(the WHERE is implied and should not be included on the command line).

=item B<-a|--authorities>

Check for duplicate authorities rather that duplicate bibliographic records.

=item B<-s|--select=s>

Repeatable. Specify how to identify which record to prefer. See the section
on SELECTORS below.

=item B<-m|--match=s>

Specifies the matching rule to use. This can be the numeric ID of a matching
rule that you have already configured (preferred), or you can specify a matching
rule on the command-line in the following format:

    <index1>/<tag1><subfield1>[##<index2>/<tag2><subfield2>[##...]]

Examples:

    at/152b##he-main/2..a##he/2..bxyzt##ident/009@
    authtype/152b##he-main,ext/2..a##he,ext/2..bxyz
    sn,ne,st-numeric/001##authtype/152b##he-main,ext/2..a##he,ext/2..bxyz

=item B<-c|--check=s>

Only relevant when you are using a matching rule specified on the command
line. Specifies sanity checks to use to ensure that the records are really
duplicate. The format is <tag1><subfields1>[,<tag2><subfields2>[,...]]

Examples:

    200abxyz will check subfields a,b,x,y,z of 200 fields
    009@,152b will check 009 data and 152$b subfields

=back

=cut

my (
    $match, $check,  $verbose,     $test_only, $help,
    $limit, $report, $authorities, @select
);
my $max_matches = 50;

my $result = GetOptions(
    'h|help'        => \$help,
    'v|verbose'     => \$verbose,
    't|test'        => \$test_only,
    'r|report'      => \$report,
    'l|limit=s'     => \$limit,
    'a|authorities' => \$authorities,
    's|select=s'    => \@select,
    'm|match=s'     => \$match,
    'c|check=s'     => \$check,
);

if ( $help || !$match ) {
    usage();
}

my $starttime = time();

my $sql =
  $authorities
  ? 'SELECT authid FROM auth_header'
  : 'SELECT biblionumber FROM biblio';

if ($limit) {
    $sql .= ' WHERE ' . $limit;
}

@select = ('date') unless @select;

my @selectors = ();

=head1 SELECTORS

This script supports a number of selectors for choosing which record
is "better."

=over 8

=cut

foreach my $sel (@select) {
    for ($sel) {

=item B<score>

Prefer the record which is the best match based on the specified matching
rule. This will probably only be useful in cases where the matching rule
will not match the source record, since the source record will automatically
be given a score of 2 * the matching rule threshold if it wasn't picked up
by the matcher.

=cut

        when (/^score$/) {
            push @selectors, sub { return $_[0]->{'score'} || 0 }
        }

=item B<date>

Prefer the record which is newer based on the 005 field.

=cut

        when (/^date$/) {
            push @selectors, sub {
                return (
                    defined $_[0]->{'record'}->field('005')
                    ? $_[0]->{'record'}->field('005')->data()
                    : 0
                );
              }
        }

=item B<source=ABC>

MARC21 only. Prefer records which come from ABC based on the 003 field.

=cut

        when (/^source=(.*)$/) {
            push @selectors, sub {
                return (
                    defined $_[0]->{'record'}->field('003')
                      && $_[0]->{'record'}->field('003')->data() eq $1
                    ? 1
                    : 0
                );
              }
        }

=item B<usage>

Authorities only. Prefer the record used in the most bibliographic records.

=cut

        when (/^usage$/) {
            if ($authorities) {
                push @selectors, sub {
                    return CountUsage( $_[0]->{'record_id'} );
                  }
            }
        }

=item B<ppn>

UNIMARC only. Prefer records which have a PPN in the 009 field.

=cut

        when (/^ppn$/) {
            push @selectors, sub {
                return defined $_[0]->{'record'}->field('009')
                  && $_[0]->{'record'}->field('009')->data() ? 1 : 0;
              }
        }
    }
}

=back

=cut

my $GetRecord;
if ($authorities) {
    $GetRecord = \&C4::AuthoritiesMarc::GetAuthority;
}
else {
    $GetRecord = \&C4::Biblio::GetBiblio;
}

my $matcher;

if ( $match =~ m#/# ) {
    my @matchers = split( '##', $match );
    my $cnt = 0;
    $matcher = C4::Matcher->new( $authorities ? 'authority' : 'biblio' );
    $matcher->threshold( 1000 * scalar(@matchers) - 1 );
    $matcher->code('TEMP');
    $matcher->description('Temporary matcher for deduplication run');
    while ( $matchers[ $cnt++ ] =~ m#^([^/]+)/([0-9]{3})(.*)$# ) {
        $matcher->add_simple_matchpoint( $1, 1000, $2, $3, 0, 0, '' );
    }
    my @checks = split( ',', $check );
    $cnt = 0;
    while ( $checks[ $cnt++ ] =~ m#^([0-9]{3})(.*)$# ) {
        $matcher->add_simple_required_check( $1, $2, 0, 0, $1, $2, 0, 0, '' );
    }
}
else {
    $matcher = C4::Matcher->fetch($match);
}

unless ($matcher) {
    die "Unrecognized matcher. Bailing out.\n";
}

print "Retrieving records for checking using query: $sql\n" if $verbose;
my $dbh = C4::Context->dbh;
my $sth = $dbh->prepare($sql);
$sth->execute();

my %merges     = ();
my %rematches  = ();
my $counter    = 0;
my $checked    = 0;
my $bibsmerged = 0;
while ( my ($recordid) = $sth->fetchrow_array() ) {
    my $record;
    $counter++;
    print "Checking for matches for record #$counter (id $recordid).\n"
      if $verbose;
    next if ( $merges{$recordid} );
    $checked++;
    $record = $GetRecord->($recordid);

    my @matches = ();
    if ( defined $matcher ) {
        @matches = $matcher->get_matches( $record, $max_matches );
    }
    if ( scalar(@matches) > 1 ) {
        print "Found matches for $recordid.\n" if $verbose;
        my $foundself;
        foreach my $rec (@matches) {
            $foundself = 1 if $rec->{'record_id'} == $recordid;
            $rec->{'record'} = $GetRecord->( $rec->{'record_id'} );
            my @weights = ();
            foreach my $selector (@selectors) {
                push @weights, $selector->($rec);
            }
            while ( scalar @weights < 5 ) { push @weights, 0; }
            $rec->{weights} = \@weights;
        }
        unless ($foundself) {
            my $rec = {
                'record_id' => $recordid,
                'score'     => $matcher->threshold() * 2,
                'record'    => $record
            };
            my @weights = ();
            foreach my $selector (@selectors) {
                push @weights, $selector->($rec);
            }
            while ( scalar @weights < 5 ) { push @weights, 0; }
            $rec->{weights} = \@weights;
        }
        @matches =
          sort {
                 $b->{'weights'}->[0] <=> $a->{'weights'}->[0]
              || $b->{'weights'}->[1] <=> $a->{'weights'}->[1]
              || $b->{'weights'}->[2] <=> $a->{'weights'}->[2]
              || $b->{'weights'}->[3] <=> $a->{'weights'}->[3]
              || $b->{'weights'}->[4] <=> $a->{'weights'}->[4]
          } @matches;
        print "Identified the following records for merging: "
          . join( ', ', map { $_->{'record_id'} } @matches ) . ".\n"
          if $verbose;
        if (   $merges{ $matches[0]->{'record_id'} }
            && $merges{ $matches[0]->{'record_id'} } !=
            $matches[0]->{'record_id'} )
        {
            print
"Preferred record $matches[0]->{'record_id'} has already been merged into $merges{$matches[0]->{'record_id'}}.\n"
              if $verbose;
            $rematches{ $matches[0]->{'record_id'} } =
              $merges{ $matches[0]->{'record_id'} };
            next;
        }
        foreach my $ii ( 0 .. $#matches ) {
            next if $merges{ $matches[$ii]->{'record_id'} };
            $merges{ $matches[$ii]->{'record_id'} } =
              $matches[0]->{'record_id'};
            if ( $ii > 0 ) {
                if ($authorities) {
                    print "Merging authority "
                      . $matches[$ii]->{'record_id'}
                      . " into "
                      . $matches[0]->{'record_id'} . ".\n"
                      if $verbose;
                    if ( !$test_only ) {
                        my $editedbibs = merge(
                            $matches[$ii]->{'record_id'},
                            $matches[$ii]->{'record'},
                            $matches[0]->{'record_id'},
                            $matches[0]->{'record'}
                        );
                        print
"Changed $editedbibs bibliographic records in the course of merging "
                          . $matches[$ii]->{'record_id'}
                          . " into "
                          . $matches[0]->{'record_id'} . ".\n"
                          if $verbose;

                        $bibsmerged += $editedbibs;
                    }
                }
                else {
                    print "Bib "
                      . $matches[$ii]->{'record_id'}
                      . " should probably be merged into "
                      . $matches[0]->{'record_id'} . ".\n";
                }
            }
        }
    }
}

$authorities = 'yes' if $authorities;
$match = $matcher->code() unless $match =~ m#/#;
$check = '(none)' unless $check;
my $endtime = time();
my $totaltime = ceil( ( $endtime - $starttime ) * 1000 );
$starttime = strftime( '%D %T', localtime($starttime) );
$endtime   = strftime( '%D %T', localtime($endtime) );

my @preferred =
  map { $_ eq $merges{$_} ? $_ : () } sort { $a <=> $b } keys %merges;
my $keepers = scalar(@preferred);
my @replaced =
  map { $_ ne $merges{$_} ? "$_ => $merges{$_}" : () }
  sort { $a <=> $b } keys %merges;
my $obsoleted = scalar(@replaced);
my @rematched =
  map { $_ ne $rematches{$_} ? "$_ (already replaced by $rematches{$_})" : () }
  sort { $a <=> $b } keys %rematches;
my $needrematch = scalar(@rematched);
my $summary     = <<_SUMMARY_;

Deduplication report
=======================================================
Match rule:                     $match
Check rule:                     $check
Selectors:                      @select
Run started at:                 $starttime
Run ended at:                   $endtime
Total run time:                 $totaltime ms
Number of records retrieved:    $counter
Number of records checked:      $checked
Number of records chosen:       $keepers
Number of records obsoleted:    $obsoleted
Records requiring relink/rerun: $needrematch
Bibs merged on authority run:   $bibsmerged
_SUMMARY_
$summary .= "\n****  Ran in test mode only  ****\n" if $test_only;

print $summary;

if ($report) {
    if (@preferred) {
        print <<_PREFERRED_HEADER_;

Records identified as preferred
-------------------------------------------------------

_PREFERRED_HEADER_

        print join( "\n", @preferred ) . "\n\n";
    }

    if (@replaced) {
        print <<_REPLACED_HEADER_;

Records replaced
-------------------------------------------------------

_REPLACED_HEADER_

        print join( "\n", @replaced ) . "\n\n";
    }

    if (@rematched) {
        print <<_REMATCHES_HEADER_;

Records requiring index update to match
-------------------------------------------------------

_REMATCHES_HEADER_

        print join( "\n", @rematched ) . "\n\n";

        print "Please re-run this script after running the linker.\n";
    }

    print $summary;
}

=head1 AUTHOR

Jared Camins-Esakov <jcamins@cpbibliography.com>

=cut
