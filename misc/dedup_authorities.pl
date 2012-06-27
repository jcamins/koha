#!/usr/bin/perl

# Copyright 2012 C & P Bibliography Services
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

use strict;
use warnings;

BEGIN {

    # find Koha's Perl modules
    # test carefully before changing this
    use FindBin;
    eval { require "$FindBin::Bin/kohalib.pl" };
}

use C4::Context;
use C4::Heading;
use C4::AuthoritiesMarc;
use MARC::Record;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
use Time::HiRes qw/time/;
use POSIX qw/strftime ceil/;

$SIG{INT} = \&interrupt;

sub usage {
    pod2usage( -verbose => 2 );
    exit;
}

my $verbose = 0;
my $test_only = 0;
my $report = 0;
my $limit;
my @keep;
my $identify;
my $want_help = 0;
my $commit = 100;

my $result = GetOptions(
    'v|verbose'      => \$verbose,
    't|test'         => \$test_only,
    'r|report'  => \$report,
    'l|limit=s' => \$limit,
    'identify=s' => \$identify,
    'keep=s' => \@keep,
    'c|commit=i'     => \$commit,
    'h|help'         => \$want_help
);

$identify = 'match-heading' unless $identify =~
    m/(mainmainentry|mainentry|any|match-heading|see-from|previous-only)/;

binmode( STDOUT, ":utf8" );

if ( not $result or $want_help ) {
    usage();
}

my $starttime = time();
my $num_auths_processed = 0;
my $num_auths_deleted  = 0;
my $num_bad_auths       = 0;
my $num_confident_decisions = 0;
my $num_questionable_decisions = 0;
my %deduped_headings;
my %deleted_authorities;

my $dbh = C4::Context->dbh;
$dbh->{AutoCommit} = 0;
process_auths();
$dbh->commit();

summary();
exit 0;

sub process_auths {
    my $where = '';
    if ($limit) {
        $where = "WHERE $limit";
    }

    my $sql = "SELECT authid, marc FROM auth_header $where ORDER BY authid DESC";
    my $sth = $dbh->prepare($sql);
    $sth->execute();

    while ( my ($authid, $marc) = $sth->fetchrow_array() ) {
        $num_auths_processed++;
        process_auth($authid, $marc);

        if ( not $test_only and ( $num_auths_processed % $commit ) == 0 ) {
            print_progress_and_commit($num_auths_processed);
        }
    }

    if ( not $test_only ) {
        $dbh->commit;
    }
}

sub process_auth {
    my ($authid, $marc) = @_;

    my @marclist = [ $identify ];
    my @and_or = [ 'and' ];
    my @excluding = [];
    my @operator = [ 'exact' ];
    my @value = [ ];

    return if ($deleted_authorities{$authid});

    my $record = MARC::Record->new_from_usmarc($marc);
    unless (defined $record) {
        $num_bad_auths++;
        return;
    }
    my $heading = _get_main_entry($record);
    unless (defined $heading) {
        $num_bad_auths++;
        return;
    }
    my $display = $heading->display_form();
    my $search = $heading->search_form();
    return unless $search;
    @value = [ $search ];
    my ($searchresults, $total_hits) = SearchAuthorities(
            @marclist, @and_or, @excluding, @operator,
            @value, 0, 20, undef, 'AuthidDesc', 1
            );
    my @auths_to_dedup = ( $authid );
    if ($total_hits > 1) {
        warn "Found duplicate for $authid [$display]\n" if $verbose;
        for my $result (@$searchresults) {
            push @auths_to_dedup, $result->{'authid'} unless ($result->{'authid'} == $authid || $deleted_authorities{$result->{'authid'}});
        }
        if ($#auths_to_dedup > 0) {
            my ($final, $num_deleted, $num_confident, $num_questionable) = _dedup(\@auths_to_dedup, \@keep);
            $deduped_headings{$display} += $num_deleted;
            $num_auths_deleted += $num_deleted;
            $num_confident_decisions += $num_confident;
            $num_questionable_decisions += $num_questionable;
        }
    }
}

sub interrupt {
    warn "**** YOU INTERRUPTED THE SCRIPT ****\n";
    summary();
    die "**** YOU INTERRUPTED THE SCRIPT ****\n";
}


sub summary {
    my $endtime = time();
    my $totaltime = ceil (($endtime - $starttime) * 1000);
    $starttime = strftime('%D %T', localtime($starttime));
    $endtime = strftime('%D %T', localtime($endtime));

    my $summary = <<_SUMMARY_;

Authority deduplication report
=======================================================
Run started at:                           $starttime
Run ended at:                             $endtime
Total run time:                           $totaltime ms
Number of authorities checked:            $num_auths_processed
Number of authorities deleted:            $num_auths_deleted
Number of authorities with errors:        $num_bad_auths
Certainty (confident/questionable):       $num_confident_decisions/$num_questionable_decisions
_SUMMARY_
    $summary .= "\n****  Ran in test mode only  ****\n" if $test_only;
    print $summary;

    if ($report) {
        print <<_DEDUPED_HEADER_;

Deduplicated headings (from most frequent to least):
-------------------------------------------------------

_DEDUPED_HEADER_
        my @keys = sort {
            $deduped_headings{$b} <=> $deduped_headings{$a} or "\L$a" cmp "\L$b"
        } keys %deduped_headings;

        foreach my $key (@keys) {
            print "$key:\t" . $deduped_headings{$key} . " occurrences\n";
        }

        print $summary;
    }
}

sub _get_main_entry {
    my $record = shift;

    my $field = $record->field(C4::Context->preference('marcflavour') eq 'UNIMARC' ? '2..' : '1..');
    if (defined $field) {
        return C4::Heading->new_from_auth_field( $field );
    }
    return undef;
}

sub _is_record1_heading_replaced_by_record2 {
    my $record1 = shift;
    my $record2 = shift;
    my @marclist = [ 'previous-only' ];
    my @and_or = [ 'and' ];
    my @excluding = [];
    my @operator = [ 'exact' ];
    my @value = [ ];
    my $heading = _get_main_entry($record1);
    if (defined $heading) {
        @value = [ $heading->search_form() ];
        my ($searchresults, $total_hits) = SearchAuthorities(
                @marclist, @and_or, @excluding, @operator,
                @value, 0, 20, undef, 'AuthidDesc', 1
                );
        my $authid2 = $record2->field('001')->data();
        return grep { $_->{'authid'} eq $authid2 } @$searchresults;
    }
    return undef;
}

sub _dedup {
    my $auths_to_dedup = shift;
    my $keep = shift;
    my $num_auths_deleted = 0;
    my $num_questionable = 0;
    my $num_confident = 0;

    my @auths;
    foreach my $auth (@$auths_to_dedup) {
        push @auths, { 'authid' => $auth, 'record' => GetAuthority($auth) };
    }
    my $delauth = undef;
#    die Data::Dumper->Dumper(@auths);

    while ($#auths > 0) {
        my $decision = 0;
        # $decision < 1 = keep first, 0 = undecided, > 1 = keep last
        for my $criteria (@$keep) {
            my ($criterion, $preferred_value) = split(':', $criteria);
            if ($criterion eq 'source') { # Only relevant for MARC21 and NORMARC
                if ($auths[0]->{'record'}->field('003')->data() eq $preferred_value && $auths[$#auths]->{'record'}->field('003')->data() ne $preferred_value) {
                    $decision++;
                } elsif ($auths[0]->{'record'}->field('003')->data() eq $preferred_value && $auths[$#auths]->{'record'}->field('003')->data() ne $preferred_value) {
                    $decision--;
                }
            } elsif ($criterion eq 'timestamp') {
                if ($auths[0]->{'record'}->field('005')->data() < $auths[$#auths]->{'record'}->field('005')->data()) {
                    $decision++;
                } elsif ($auths[0]->{'record'}->field('005')->data() > $auths[$#auths]->{'record'}->field('005')->data()) {
                    $decision--;
                }
            } elsif ($criterion eq 'heading') {
                if (_is_record1_heading_replaced_by_record2($auths[0]->{'record'}, $auths[$#auths]->{'record'})) {
                    $decision++;
                } elsif (_is_record1_heading_replaced_by_record2($auths[$#auths]->{'record'}, $auths[0]->{'record'})) {
                    $decision--;
                }
            }
        }
        if ($decision == 0) { # We'll keep the first if it's a toss-up
            $num_questionable++;
            $delauth = pop @auths;
        } elsif ($decision < 0) {
            $num_confident++;
            $delauth = pop @auths;
        } else {
            $num_confident++;
            $delauth = shift @auths;
        }
        if (defined $delauth && defined $delauth->{'authid'}) {
            if (not $test_only) {
                DelAuthority($delauth->{'authid'});
            }
            $deleted_authorities{$delauth->{'authid'}} = 1;
            $num_auths_deleted++;
            undef $delauth;
        }
    }
    return $auths[0]->{'authid'}, $num_auths_deleted, $num_confident, $num_questionable;
}

sub print_progress_and_commit {
    my $recs = shift;
    $dbh->commit();
    print "... processed $recs records\n";
}

=head1 NAME

dedup_authorities.pl

=head1 SYNOPSIS

  dedup_authorities.pl
  dedup_authorities.pl -v
  dedup_authorities.pl -f
  dedup_authorities.pl --commit=1000
  dedup_authorities.pl --keep=source --identify=mainentry

=head1 DESCRIPTION

This batch job deletes duplicate authorities according to user-defined criteria.

=over 8

=item B<--help>

Prints this help

=item B<-v|--verbose>

Provide verbose log information (print a warning of every authority with duplicates).

=item B<--commit=N>

Commit the results to the database after every N records are processed.

=item B<--test>

Only test the authority deduplicator and report the results; do not delete any
records.

=item B<-r|--report>

Print a report of all the authorities that were deleted.

=item B<-l|--limit>

Only process those authority records that match the user-specified WHERE clause.
Note that this limits only the initial search, not the entire domain in which
the tool looks for duplicates (so, for example, if the specified limit includes
only one of the two authorities for a given heading, the other heading may be
deleted if it matches the tool's heuristics).

=item B<--identify=STRING>

Choose how to find duplicate authorities. Valid options are as follows:

=over 4

=item B<mainmainentry> - look only in subfield $a of the main entry

=item B<mainentry> - look only in the main entry

=item B<any> - look anywhere in the record

=item B<match-heading> - look for duplicates in any headings (default)

=item B<see-from> - only look for duplicates where the main entry of one record
is used as a see-from entry in another record

=item B<previous-only> - only look for duplicates where the main entry of one record
is listed as a previous form of heading in another record (MARC21 only)

=back

=item B<--keep=STRING>

Repeatable. Choose how to decide which authority to keep. Valid options are as follows:

=over 4

=item B<source:CODE> - prefer authorities with CODE in the 003 (MARC21 only)

=item B<timestamp> - prefer authorities that are newer based on the 005

=item B<heading> - prefer authorities that have the heading listed as a previous
form (MARC21 only)

=back

=back

=head1 SEE ALSO

misc/link_bibs_to_authorities.pl, misc/flip_headings.pl

=head1 AUTHOR

Jared Camins-Esakov, C & P Bibliography Services, E<lt>jcamins@cpbibliography.comE<gt>

=cut
