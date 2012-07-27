package C4::ZebraIndex;

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

# This module contains utility functions to index records in Zebra
# It is a temporary place to store rebuild_zebra.pl subs in order for them to be
# used by other scripts (misc/migration_tools/dedup_authorities.pl for example)
# As soon as the new indexation layer is in place, and all scripts using this
# module are updated, this module have to be removed.

use Modern::Perl;
use POSIX;
use File::Temp qw/tempdir/;
use MARC::Record;

use C4::Context;
use C4::Biblio;
use C4::AuthoritiesMarc;
use C4::Items;
use XML::LibXML;
use Koha::RecordProcessor;

sub IndexRecord {
    my ($recordtype, $recordids, $options) = @_;

    my $as_xml = ($options and $options->{as_xml}) ? 1 : 0;
    my $noxml = ($options and $options->{noxml}) ? 1 : 0;
    my $nosanitize = ($options and $options->{nosanitize}) ? $as_xml : 0;
    my $reset_index = ($options and $options->{reset_index}) ? 1 : 0;
    my $noshadow = ($options and $options->{noshadow}) ? " -n " : "";
    my $record_format = ($options and $options->{record_format})
                    ? $options->{record_format}
                    : ($as_xml)
                        ? 'marcxml'
                        : 'iso2709';
    my $zebraidx_log_opt = ($options and defined $options->{zebraidx_log_opt})
                        ? $options->{zebraidx_log_opt}
                        : "";
    my $verbose = ($options and $options->{verbose}) ? 1 : 0;
    my $skip_export = ($options and $options->{skip_export}) ? 1 : 0;
    my $skip_index = ($options and $options->{skip_index}) ? 1 : 0;
    my $keep_export = ($options and $options->{keep_export}) ? 1 : 0;
    my $directory = ($options and $options->{directory})
                    ? $options->{directory}
                    : tempdir(CLEANUP => ($keep_export ? 0 : 1));

    my @recordids = (ref $recordids eq "ARRAY") ? @$recordids : split (/ /, $recordids);
    @recordids = map { { biblio_auth_number => $_ } } @recordids;

    my $num_exported = 0;
    unless ($skip_export) {
        $num_exported = _export_marc_records_from_list($recordtype, \@recordids,
            $directory, $as_xml, $noxml, $nosanitize, $verbose);
    }
    unless ($skip_index) {
        _do_indexing($recordtype, "update", $directory, $reset_index, $noshadow,
            $record_format, $zebraidx_log_opt);
    }

    return $num_exported;
}

sub DeleteRecordIndex {
    my ($recordtype, $recordids, $options) = @_;

    my $as_xml = ($options and $options->{as_xml}) ? 1 : 0;
    my $noshadow = ($options and $options->{noshadow}) ? " -n " : "";
    my $record_format = ($options and $options->{record_format})
                    ? $options->{record_format}
                    : ($as_xml)
                        ? 'marcxml'
                        : 'iso2709';
    my $zebraidx_log_opt = ($options and defined $options->{zebraidx_log_opt})
                        ? $options->{zebraidx_log_opt}
                        : "";
    my $verbose = ($options and $options->{verbose}) ? 1 : 0;
    my $skip_export = ($options and $options->{skip_export}) ? 1 : 0;
    my $skip_index = ($options and $options->{skip_index}) ? 1 : 0;
    my $keep_export = ($options and $options->{keep_export}) ? 1 : 0;
    my $directory = ($options and $options->{directory})
                    ? $options->{directory}
                    : tempdir(CLEANUP => ($keep_export ? 0 : 1));

    my @recordids = (ref $recordids eq "ARRAY") ? @$recordids : split (/ /, $recordids);
    @recordids = map { { biblio_auth_number => $_ } } @recordids;

    my $num_exported = 0;
    unless ($skip_export) {
        $num_exported = _generate_deleted_marc_records($recordtype, \@recordids,
            $directory, $as_xml, $verbose);
    }
    unless ($skip_index) {
        _do_indexing($recordtype, "adelete", $directory, 0, $noshadow,
            $record_format, $zebraidx_log_opt);
    }

    return $num_exported;
}


sub _export_marc_records_from_list {
    my ( $record_type, $entries, $directory, $as_xml, $noxml, $nosanitize, $verbose ) = @_;

    my $num_exported = 0;
    open my $fh, ">:encoding(UTF-8) ", "$directory/exported_records" or die $!;
    if (_include_xml_wrapper($as_xml, $record_type)) {
        # include XML declaration and root element
        print {$fh} '<?xml version="1.0" encoding="UTF-8"?><collection>';
    }
    my $i     = 0;
    my %found = ();
    my ($itemtag) = GetMarcFromKohaField("items.itemnumber",'');
    my $tester = XML::LibXML->new();
    foreach my $record_number (
        map  { $_->{biblio_auth_number} }
        grep { !$found{ $_->{biblio_auth_number} }++ } @$entries
    ) {
        if($nosanitize) {
            my $marcxml = $record_type eq 'biblio'
                        ? GetXmlBiblio($record_number)
                        : GetAuthorityXML($record_number);
            if ($record_type eq 'biblio'){
                my @items = GetItemsInfo($record_number);
                if (@items){
                    my $record = MARC::Record->new;
                    $record->encoding('UTF-8');
                    my @itemsrecord;
                    foreach my $item (@items){
                        my $record = Item2Marc($item, $record_number);
                        push @itemsrecord, $record->field($itemtag);
                    }
                    $record->insert_fields_ordered(@itemsrecord);
                    my $itemsxml = $record->as_xml_record();
                    $marcxml =
                        substr($marcxml, 0, length($marcxml)-10) .
                        substr($itemsxml, index($itemsxml, "</leader>\n", 0) + 10);
                }
            }
            # extra test to ensure that result is valid XML; otherwise
            # Zebra won't parse it in DOM mode
            eval {
                my $doc = $tester->parse_string($marcxml);
            };
            if ($@) {
                warn "Error exporting record $record_number ($record_type): $@\n";
                next;
            }
            if ($marcxml) {
                $marcxml =~ s!<\?xml version="1.0" encoding="UTF-8"\?>\n!!;
                print {$fh} $marcxml;
                $num_exported++;
            }
        } else {
            my ($marc) = _get_corrected_marc_record( $record_type, $record_number, $noxml );
            if ( defined $marc ) {
                eval {
                    my $rec;
                    if ($as_xml) {
                        $rec = $marc->as_xml_record(C4::Context->preference('marcflavour'));
                        eval {
                            my $doc = $tester->parse_string($rec);
                        };
                        if ($@) {
                            die "invalid XML: $@";
                        }
                        $rec =~ s!<\?xml version="1.0" encoding="UTF-8"\?>\n!!;
                    } else {
                        $rec = $marc->as_usmarc();
                    }
                    print {$fh} $rec;
                    $num_exported++;
                };
                if ($@) {
                    warn "Error exporting record $record_number ($record_type) ".($noxml ? "not XML" : "XML");
                    warn "... specific error is $@" if $verbose;
                }
            }
        }
        $i++;
        if($verbose) {
            print ".";
            print "$i\n" unless($i % 100);
        }
    }
    print {$fh} '</collection>' if (_include_xml_wrapper($as_xml, $record_type));
    close $fh;
    print "\n$num_exported records exported to $directory/exported_records\n" if $verbose;
    return $num_exported;
}

sub _generate_deleted_marc_records {
    my ( $record_type, $entries, $directory, $as_xml, $verbose ) = @_;

    my $num_exported = 0;
    open my $fh, ">:encoding(UTF-8)", "$directory/exported_records" or die $!;
    if (_include_xml_wrapper($as_xml, $record_type)) {
        # include XML declaration and root element
        print {$fh} '<?xml version="1.0" encoding="UTF-8"?><collection>';
    }
    my $i = 0;
    foreach my $record_number ( map { $_->{biblio_auth_number} } @$entries ) {
        my $marc = MARC::Record->new();
        if ( $record_type eq 'biblio' ) {
            _fix_biblio_ids( $marc, $record_number, $record_number );
        } else {
            _fix_authority_id( $marc, $record_number );
        }
        if ( C4::Context->preference("marcflavour") eq "UNIMARC" ) {
            _fix_unimarc_100($marc);
        }

        my $rec;
        if ($as_xml) {
            $rec = $marc->as_xml_record(C4::Context->preference('marcflavour'));
            $rec =~ s!<\?xml version="1.0" encoding="UTF-8"\?>\n!!;
        } else {
            $rec = $marc->as_usmarc();
        }
        print {$fh} $rec;

        $num_exported++;
        $i++;
        if($verbose) {
            print ".";
            print "$i\n" unless($i % 100);
        }
    }
    print {$fh} '</collection>' if (_include_xml_wrapper($as_xml, $record_type));
    close $fh;

    return $num_exported;
}

sub _get_corrected_marc_record {
    my ( $record_type, $record_number, $noxml ) = @_;

    my $marc = _get_raw_marc_record( $record_type, $record_number, $noxml );

    if ( defined $marc ) {
        _fix_leader($marc);
        if ( $record_type eq 'authority' ) {
            _fix_authority_id( $marc, $record_number );
        } elsif ($record_type eq 'biblio' && C4::Context->preference('IncludeSeeFromInSearches')) {
            my $normalizer = Koha::RecordProcessor->new( { filters => 'EmbedSeeFromHeadings' } );
            $marc = $normalizer->process($marc);
        }
        if ( C4::Context->preference("marcflavour") eq "UNIMARC" ) {
            _fix_unimarc_100($marc);
        }
    }

    return $marc;
}

sub _get_raw_marc_record {
    my ( $record_type, $record_number, $noxml ) = @_;

    my $dbh = C4::Context->dbh;
    my $marc;
    if ( $record_type eq 'biblio' ) {
        if ($noxml) {
            my $fetch_sth = $dbh->prepare_cached("SELECT marc FROM biblioitems
                WHERE biblionumber = ?");
            $fetch_sth->execute($record_number);
            if ( my ($blob) = $fetch_sth->fetchrow_array ) {
                $marc = MARC::Record->new_from_usmarc($blob);
                unless ($marc) {
                    warn "error creating MARC::Record from $blob";
                }
            }
            # failure to find a bib is not a problem -
            # a delete could have been done before
            # trying to process a record update

            $fetch_sth->finish();
            return unless $marc;
        } else {
            eval { $marc = GetMarcBiblio($record_number, 1); };
            if ($@ || !$marc) {
                # here we do warn since catching an exception
                # means that the bib was found but failed
                # to be parsed
                warn "error retrieving biblio $record_number: $@";
                return;
            }
        }
    } else {
        eval { $marc = C4::AuthoritiesMarc::GetAuthority($record_number); };
        if ($@) {
            warn "error retrieving authority $record_number: $@";
            return;
        }
    }
    return $marc;
}

sub _fix_leader {

    # FIXME - this routine is suspect
    # It blanks the Leader/00-05 and Leader/12-16 to
    # force them to be recalculated correct when
    # the $marc->as_usmarc() or $marc->as_xml() is called.
    # But why is this necessary?  It would be a serious bug
    # in MARC::Record (definitely) and MARC::File::XML (arguably)
    # if they are emitting incorrect leader values.
    my $marc = shift;

    my $leader = $marc->leader;
    substr( $leader, 0,  5 ) = '     ';
    substr( $leader, 10, 7 ) = '22     ';
    $marc->leader( substr( $leader, 0, 24 ) );
}


sub _fix_biblio_ids {

    # FIXME - it is essential to ensure that the biblionumber is present,
    #         otherwise, Zebra will choke on the record.  However, this
    #         logic belongs in the relevant C4::Biblio APIs.
    my $marc         = shift;
    my $biblionumber = shift;
    my $dbh = C4::Context->dbh;
    my $biblioitemnumber;
    if (@_) {
        $biblioitemnumber = shift;
    } else {
        my $sth = $dbh->prepare(
            "SELECT biblioitemnumber FROM biblioitems WHERE biblionumber=?");
        $sth->execute($biblionumber);
        ($biblioitemnumber) = $sth->fetchrow_array;
        $sth->finish;
        unless ($biblioitemnumber) {
            warn "failed to get biblioitemnumber for biblio $biblionumber";
            return 0;
        }
    }

    # FIXME - this is cheating on two levels
    # 1. C4::Biblio::_koha_marc_update_bib_ids is meant to be an internal function
    # 2. Making sure that the biblionumber and biblioitemnumber are correct and
    #    present in the MARC::Record object ought to be part of GetMarcBiblio.
    #
    # On the other hand, this better for now than what rebuild_zebra.pl used to
    # do, which was duplicate the code for inserting the biblionumber
    # and biblioitemnumber
    C4::Biblio::_koha_marc_update_bib_ids( $marc, '', $biblionumber, $biblioitemnumber );

    return 1;
}

sub _fix_authority_id {

    # FIXME - as with fix_biblio_ids, the authid must be present
    #         for Zebra's sake.  However, this really belongs
    #         in C4::AuthoritiesMarc.
    my ( $marc, $authid ) = @_;
    unless ( $marc->field('001') and $marc->field('001')->data() eq $authid ) {
        $marc->delete_field( $marc->field('001') );
        $marc->insert_fields_ordered( MARC::Field->new( '001', $authid ) );
    }
}

sub _fix_unimarc_100 {

    # FIXME - again, if this is necessary, it belongs in C4::AuthoritiesMarc.
    my $marc = shift;

    my $string;
    if ( length( $marc->subfield( 100, "a" ) ) == 36 ) {
        $string = $marc->subfield( 100, "a" );
        my $f100 = $marc->field(100);
        $marc->delete_field($f100);
    } else {
        $string = POSIX::strftime( "%Y%m%d", localtime );
        $string =~ s/\-//g;
        $string = sprintf( "%-*s", 35, $string );
    }
    substr( $string, 22, 6, "frey50" );
    unless ( length( $marc->subfield( 100, "a" ) ) == 36 ) {
        $marc->delete_field( $marc->field(100) );
        $marc->insert_grouped_field( MARC::Field->new( 100, "", "", "a" => $string ) );
    }
}

sub _do_indexing {
    my ( $record_type, $op, $record_dir, $reset_index, $noshadow, $record_format, $zebraidx_log_opt ) = @_;

    my $zebra_server  = ( $record_type eq 'biblio' ) ? 'biblioserver' : 'authorityserver';
    my $zebra_db_name = ( $record_type eq 'biblio' ) ? 'biblios'      : 'authorities';
    my $zebra_config  = C4::Context->zebraconfig($zebra_server)->{'config'};
    my $zebra_db_dir  = C4::Context->zebraconfig($zebra_server)->{'directory'};

    system("zebraidx -c $zebra_config $zebraidx_log_opt -g $record_format -d $zebra_db_name init") if $reset_index;
    system("zebraidx -c $zebra_config $zebraidx_log_opt $noshadow -g $record_format -d $zebra_db_name $op $record_dir");
    system("zebraidx -c $zebra_config $zebraidx_log_opt -g $record_format -d $zebra_db_name commit") unless $noshadow;

}

sub _include_xml_wrapper {
    my $as_xml = shift;
    my $record_type = shift;

    my $bib_index_mode = C4::Context->config('zebra_bib_index_mode') || 'grs1';
    my $auth_index_mode = C4::Context->config('zebra_auth_index_mode') || 'dom';

    return 0 unless $as_xml;
    return 1 if $record_type eq 'biblio' and $bib_index_mode eq 'dom';
    return 1 if $record_type eq 'authority' and $auth_index_mode eq 'dom';
    return 0;

}

1;
