#!/usr/bin/perl

use strict;
#use warnings; FIXME - Bug 2505

use C4::Context;
use Getopt::Long;
use File::Temp qw/ tempdir /;
use File::Path;
use C4::Biblio;
use C4::AuthoritiesMarc;
use C4::Items;
use C4::ZebraIndex;

# script that checks zebradir structure & create directories & mandatory files if needed
#
#

$|=1; # flushes output
# If the cron job starts us in an unreadable dir, we will break without
# this.
chdir $ENV{HOME} if (!(-r '.'));
my $directory;
my $nosanitize;
my $skip_export;
my $keep_export;
my $skip_index;
my $reset;
my $biblios;
my $authorities;
my $noxml;
my $noshadow;
my $do_munge;
my $want_help;
my $as_xml;
my $process_zebraqueue;
my $do_not_clear_zebraqueue;
my $length;
my $where;
my $offset;
my $run_as_root;
my $run_user = (getpwuid($<))[0];

my $verbose_logging = 0;
my $zebraidx_log_opt = " -v none,fatal,warn ";
my $result = GetOptions(
    'd:s'           => \$directory,
    'r|reset'       => \$reset,
    's'             => \$skip_export,
    'k'             => \$keep_export,
    'I|skip-index'  => \$skip_index,
    'nosanitize'    => \$nosanitize,
    'b'             => \$biblios,
    'noxml'         => \$noxml,
    'w'             => \$noshadow,
    'munge-config'  => \$do_munge,
    'a'             => \$authorities,
    'h|help'        => \$want_help,
    'x'             => \$as_xml,
    'y'             => \$do_not_clear_zebraqueue,
    'z'             => \$process_zebraqueue,
    'where:s'        => \$where,
    'length:i'        => \$length,
    'offset:i'      => \$offset,
    'v+'             => \$verbose_logging,
    'run-as-root'    => \$run_as_root,
);

if (not $result or $want_help) {
    print_usage();
    exit 0;
}

if( not defined $run_as_root and $run_user eq 'root') {
    my $msg = "Warning: You are running this script as the user 'root'.\n";
    $msg   .= "If this is intentional you must explicitly specify this using the -run-as-root switch\n";
    $msg   .= "Please do '$0 --help' to see usage.\n";
    die $msg;
}

if (not $biblios and not $authorities) {
    my $msg = "Must specify -b or -a to reindex bibs or authorities\n";
    $msg   .= "Please do '$0 --help' to see usage.\n";
    die $msg;
}

if ( !$as_xml and $nosanitize ) {
    my $msg = "Cannot specify both -no_xml and -nosanitize\n";
    $msg   .= "Please do '$0 --help' to see usage.\n";
    die $msg;
}

if ($process_zebraqueue and ($skip_export or $reset)) {
    my $msg = "Cannot specify -r or -s if -z is specified\n";
    $msg   .= "Please do '$0 --help' to see usage.\n";
    die $msg;
}

if ($process_zebraqueue and $do_not_clear_zebraqueue) {
    my $msg = "Cannot specify both -y and -z\n";
    $msg   .= "Please do '$0 --help' to see usage.\n";
    die $msg;
}

if ($reset) {
    $noshadow = 1;
}

if ($noshadow) {
    $noshadow = ' -n ';
}

#  -v is for verbose, which seems backwards here because of how logging is set
#    on the CLI of zebraidx.  It works this way.  The default is to not log much
if ($verbose_logging >= 2) {
    $zebraidx_log_opt = '-v none,fatal,warn,all';
}

my $use_tempdir = 0;
unless ($directory) {
    $use_tempdir = 1;
    $directory = tempdir(CLEANUP => ($keep_export ? 0 : 1));
}


my $biblioserverdir = C4::Context->zebraconfig('biblioserver')->{directory};
my $authorityserverdir = C4::Context->zebraconfig('authorityserver')->{directory};

my $kohadir = C4::Context->config('intranetdir');
my $bib_index_mode = C4::Context->config('zebra_bib_index_mode') || 'grs1';
my $auth_index_mode = C4::Context->config('zebra_auth_index_mode') || 'dom';

my $dbh = C4::Context->dbh;
my ($biblionumbertagfield,$biblionumbertagsubfield) = &GetMarcFromKohaField("biblio.biblionumber","");
my ($biblioitemnumbertagfield,$biblioitemnumbertagsubfield) = &GetMarcFromKohaField("biblioitems.biblioitemnumber","");

if ( $verbose_logging ) {
    print "Zebra configuration information\n";
    print "================================\n";
    print "Zebra biblio directory      = $biblioserverdir\n";
    print "Zebra authorities directory = $authorityserverdir\n";
    print "Koha directory              = $kohadir\n";
    print "BIBLIONUMBER in :     $biblionumbertagfield\$$biblionumbertagsubfield\n";
    print "BIBLIOITEMNUMBER in : $biblioitemnumbertagfield\$$biblioitemnumbertagsubfield\n";
    print "================================\n";
}

if ($do_munge) {
    munge_config();
}

my $tester = XML::LibXML->new();

if ($authorities) {
    index_records('authority', $directory, $skip_export, $skip_index, $process_zebraqueue, $as_xml, $noxml, $nosanitize, $do_not_clear_zebraqueue, $verbose_logging, $zebraidx_log_opt, $authorityserverdir);
} else {
    print "skipping authorities\n" if ( $verbose_logging );
}

if ($biblios) {
    index_records('biblio', $directory, $skip_export, $skip_index, $process_zebraqueue, $as_xml, $noxml, $nosanitize, $do_not_clear_zebraqueue, $verbose_logging, $zebraidx_log_opt, $biblioserverdir);
} else {
    print "skipping biblios\n" if ( $verbose_logging );
}


if ( $verbose_logging ) {
    print "====================\n";
    print "CLEANING\n";
    print "====================\n";
}
if ($keep_export) {
    print "NOTHING cleaned : the export $directory has been kept.\n";
    print "You can re-run this script with the -s and -d $directory parameters";
    print "\n";
    print "if you just want to rebuild zebra after changing the record.abs\n";
    print "or another zebra config file\n";
} else {
    unless ($use_tempdir) {
        # if we're using a temporary directory
        # created by File::Temp, it will be removed
        # automatically.
        rmtree($directory, 0, 1);
        print "directory $directory deleted\n";
    }
}

# This checks to see if the zebra directories exist under the provided path.
# If they don't, then zebra is likely to spit the dummy. This returns true
# if the directories had to be created, false otherwise.
sub check_zebra_dirs {
    my ($base) = shift() . '/';
    my $needed_repairing = 0;
    my @dirs = ( '', 'key', 'register', 'shadow', 'tmp' );
    foreach my $dir (@dirs) {
        my $bdir = $base . $dir;
        if (! -d $bdir) {
            $needed_repairing = 1;
            mkdir $bdir || die "Unable to create '$bdir': $!\n";
            print "$0: needed to create '$bdir'\n";
        }
    }
    return $needed_repairing;
}   # ----------  end of subroutine check_zebra_dirs  ----------

sub index_records {
    my ($record_type, $directory, $skip_export, $skip_index, $process_zebraqueue, $as_xml, $noxml, $nosanitize, $do_not_clear_zebraqueue, $verbose_logging, $zebraidx_log_opt, $server_dir) = @_;

    my $need_reset = check_zebra_dirs($server_dir);
    if ($need_reset) {
        print "$0: found broken zebra server directories: forcing a rebuild\n";
        $reset = 1;
    }

    if ( $verbose_logging ) {
        print "====================\n";
        print "REINDEXING zebra\n";
        print "====================\n";
    }

    my $record_fmt = ($as_xml) ? 'marcxml' : 'iso2709' ;
    if ($process_zebraqueue) {
        # Process 'deleted' records
        my $entries = select_zebraqueue_records( $record_type, 'deleted' );
        my @entries_to_delete = map { $_->{biblio_auth_id} } @$entries;

        C4::ZebraIndex::DeleteRecordIndex($record_type, \@entries_to_delete, {
            as_xml => $as_xml, noshadow => $noshadow, record_format => $record_fmt,
            zebraidx_log_opt => $zebraidx_log_opt, verbose => $verbose_logging,
            skip_export => $skip_export, skip_index => $skip_index,
            keep_export => $keep_export, directory => $directory
        });

        mark_zebraqueue_batch_done($entries);

        # Process 'updated' records'
        $entries = select_zebraqueue_records( $record_type, 'updated' );
        my @entries_to_update = map {
            my $id = $_->{biblio_auth_id};
            # do not try to update deleted records
            (0 == grep { $id == $_ } @entries_to_delete) ? $id : ()
        } @$entries;

        C4::ZebraIndex::IndexRecord($record_type, \@entries_to_update, {
            as_xml => $as_xml, noxml => $noxml, reset_index => $reset,
            noshadow => $noshadow, record_format => $record_fmt,
            zebraidx_log_opt => $zebraidx_log_opt, verbose => $verbose_logging,
            skip_export => $skip_export, skip_index => $skip_index,
            keep_export => $keep_export, directory => $directory
        });

        mark_zebraqueue_batch_done($entries);
    } else {
        my $sth = select_all_records($record_type);
        my $entries = $sth->fetchall_arrayref([]);
        my @entries_to_update = map { $_->[0] } @$entries;

        C4::ZebraIndex::IndexRecord($record_type, \@entries_to_update, {
            as_xml => $as_xml, noxml => $noxml, reset_index => $reset,
            noshadow => $noshadow, record_format => $record_fmt,
            zebraidx_log_opt => $zebraidx_log_opt, nosanitize => $nosanitize,
            verbose => $verbose_logging, skip_export => $skip_export,
            skip_index => $skip_index, keep_export => $keep_export,
            directory => $directory
        });

        unless ($do_not_clear_zebraqueue) {
            mark_all_zebraqueue_done($record_type);
        }
    }
}


sub select_zebraqueue_records {
    my ($record_type, $update_type) = @_;

    my $server = ($record_type eq 'biblio') ? 'biblioserver' : 'authorityserver';
    my $op = ($update_type eq 'deleted') ? 'recordDelete' : 'specialUpdate';

    my $sth = $dbh->prepare("SELECT id, biblio_auth_number
                             FROM zebraqueue
                             WHERE server = ?
                             AND   operation = ?
                             AND   done = 0
                             ORDER BY id DESC");
    $sth->execute($server, $op);
    my $entries = $sth->fetchall_arrayref({});
}

sub mark_all_zebraqueue_done {
    my ($record_type) = @_;

    my $server = ($record_type eq 'biblio') ? 'biblioserver' : 'authorityserver';

    my $sth = $dbh->prepare("UPDATE zebraqueue SET done = 1
                             WHERE server = ?
                             AND done = 0");
    $sth->execute($server);
}

sub mark_zebraqueue_batch_done {
    my ($entries) = @_;

    $dbh->{AutoCommit} = 0;
    my $sth = $dbh->prepare("UPDATE zebraqueue SET done = 1 WHERE id = ?");
    $dbh->commit();
    foreach my $id (map { $_->{id} } @$entries) {
        $sth->execute($id);
    }
    $dbh->{AutoCommit} = 1;
}

sub select_all_records {
    my $record_type = shift;
    return ($record_type eq 'biblio') ? select_all_biblios() : select_all_authorities();
}

sub select_all_authorities {
    my $strsth=qq{SELECT authid FROM auth_header};
    $strsth.=qq{ WHERE $where } if ($where);
    $strsth.=qq{ LIMIT $length } if ($length && !$offset);
    $strsth.=qq{ LIMIT $offset,$length } if ($length && $offset);
    my $sth = $dbh->prepare($strsth);
    $sth->execute();
    return $sth;
}

sub select_all_biblios {
    my $strsth = qq{ SELECT biblionumber FROM biblioitems };
    $strsth.=qq{ WHERE $where } if ($where);
    $strsth.=qq{ LIMIT $length } if ($length && !$offset);
    $strsth.=qq{ LIMIT $offset,$length } if ($offset);
    my $sth = $dbh->prepare($strsth);
    $sth->execute();
    return $sth;
}


sub print_usage {
    print <<_USAGE_;
$0: reindex MARC bibs and/or authorities in Zebra.

Use this batch job to reindex all biblio or authority
records in your Koha database.

Parameters:

    -b                      index bibliographic records

    -a                      index authority records

    -z                      select only updated and deleted
                            records marked in the zebraqueue
                            table.  Cannot be used with -r
                            or -s.

    -r                      clear Zebra index before
                            adding records to index. Implies -w.

    -d                      Temporary directory for indexing.
                            If not specified, one is automatically
                            created.  The export directory
                            is automatically deleted unless
                            you supply the -k switch.

    -k                      Do not delete export directory.

    -s                      Skip export.  Used if you have
                            already exported the records
                            in a previous run.

    -noxml                  index from ISO MARC blob
                            instead of MARC XML.  This
                            option is recommended only
                            for advanced user.

    -x                      export and index as xml instead of is02709 (biblios only).
                            use this if you might have records > 99,999 chars,

    -nosanitize             export biblio/authority records directly from DB marcxml
                            field without sanitizing records. It speed up
                            dump process but could fail if DB contains badly
                            encoded records. Works only with -x,

    -w                      skip shadow indexing for this batch

    -y                      do NOT clear zebraqueue after indexing; normally,
                            after doing batch indexing, zebraqueue should be
                            marked done for the affected record type(s) so that
                            a running zebraqueue_daemon doesn't try to reindex
                            the same records - specify -y to override this.
                            Cannot be used with -z.

    -v                      increase the amount of logging.  Normally only
                            warnings and errors from the indexing are shown.
                            Use log level 2 (-v -v) to include all Zebra logs.

    --length   1234         how many biblio you want to export
    --offset 1243           offset you want to start to
                                example: --offset 500 --length=500 will result in a LIMIT 500,1000 (exporting 1000 records, starting by the 500th one)
                                note that the numbers are NOT related to biblionumber, that's the intended behaviour.
    --where                 let you specify a WHERE query, like itemtype='BOOK'
                            or something like that

    --munge-config          Deprecated option to try
                            to fix Zebra config files.

    --run-as-root           explicitily allow script to run as 'root' user

    --help or -h            show this message.
_USAGE_
}

# FIXME: the following routines are deprecated and
# will be removed once it is determined whether
# a script to fix Zebra configuration files is
# actually needed.
sub munge_config {
#
# creating zebra-biblios.cfg depending on system
#

# getting zebraidx directory
my $zebraidxdir;
foreach (qw(/usr/local/bin/zebraidx
        /opt/bin/zebraidx
        /usr/bin/zebraidx
        )) {
    if ( -f $_ ) {
        $zebraidxdir=$_;
    }
}

unless ($zebraidxdir) {
    print qq|
    ERROR: could not find zebraidx directory
    ERROR: Either zebra is not installed,
    ERROR: or it's in a directory I don't checked.
    ERROR: do a which zebraidx and edit this file to add the result you get
|;
    exit;
}
$zebraidxdir =~ s/\/bin\/.*//;
print "Info : zebra is in $zebraidxdir \n";

# getting modules directory
my $modulesdir;
foreach (qw(/usr/local/lib/idzebra-2.0/modules/mod-grs-xml.so
            /usr/local/lib/idzebra/modules/mod-grs-xml.so
            /usr/lib/idzebra/modules/mod-grs-xml.so
            /usr/lib/idzebra-2.0/modules/mod-grs-xml.so
        )) {
    if ( -f $_ ) {
        $modulesdir=$_;
    }
}

unless ($modulesdir) {
    print qq|
    ERROR: could not find mod-grs-xml.so directory
    ERROR: Either zebra is not properly compiled (libxml2 is not setup and you don t have mod-grs-xml.so,
    ERROR: or it's in a directory I don't checked.
    ERROR: find where mod-grs-xml.so is and edit this file to add the result you get
|;
    exit;
}
$modulesdir =~ s/\/modules\/.*//;
print "Info: zebra modules dir : $modulesdir\n";

# getting tab directory
my $tabdir;
foreach (qw(/usr/local/share/idzebra/tab/explain.att
            /usr/local/share/idzebra-2.0/tab/explain.att
            /usr/share/idzebra/tab/explain.att
            /usr/share/idzebra-2.0/tab/explain.att
        )) {
    if ( -f $_ ) {
        $tabdir=$_;
    }
}

unless ($tabdir) {
    print qq|
    ERROR: could not find explain.att directory
    ERROR: Either zebra is not properly compiled,
    ERROR: or it's in a directory I don't checked.
    ERROR: find where explain.att is and edit this file to add the result you get
|;
    exit;
}
$tabdir =~ s/\/tab\/.*//;
print "Info: tab dir : $tabdir\n";

#
# AUTHORITIES creating directory structure
#
my $created_dir_or_file = 0;
if ($authorities) {
    if ( $verbose_logging ) {
        print "====================\n";
        print "checking directories & files for authorities\n";
        print "====================\n";
    }
    unless (-d "$authorityserverdir") {
        system("mkdir -p $authorityserverdir");
        print "Info: created $authorityserverdir\n";
        $created_dir_or_file++;
    }
    unless (-d "$authorityserverdir/lock") {
        mkdir "$authorityserverdir/lock";
        print "Info: created $authorityserverdir/lock\n";
        $created_dir_or_file++;
    }
    unless (-d "$authorityserverdir/register") {
        mkdir "$authorityserverdir/register";
        print "Info: created $authorityserverdir/register\n";
        $created_dir_or_file++;
    }
    unless (-d "$authorityserverdir/shadow") {
        mkdir "$authorityserverdir/shadow";
        print "Info: created $authorityserverdir/shadow\n";
        $created_dir_or_file++;
    }
    unless (-d "$authorityserverdir/tab") {
        mkdir "$authorityserverdir/tab";
        print "Info: created $authorityserverdir/tab\n";
        $created_dir_or_file++;
    }
    unless (-d "$authorityserverdir/key") {
        mkdir "$authorityserverdir/key";
        print "Info: created $authorityserverdir/key\n";
        $created_dir_or_file++;
    }

    unless (-d "$authorityserverdir/etc") {
        mkdir "$authorityserverdir/etc";
        print "Info: created $authorityserverdir/etc\n";
        $created_dir_or_file++;
    }

    #
    # AUTHORITIES : copying mandatory files
    #
    # the record model, depending on marc flavour
    unless (-f "$authorityserverdir/tab/record.abs") {
        if (C4::Context->preference("marcflavour") eq "UNIMARC") {
            system("cp -f $kohadir/etc/zebradb/marc_defs/unimarc/authorities/record.abs $authorityserverdir/tab/record.abs");
            print "Info: copied record.abs for UNIMARC\n";
        } else {
            system("cp -f $kohadir/etc/zebradb/marc_defs/marc21/authorities/record.abs $authorityserverdir/tab/record.abs");
            print "Info: copied record.abs for USMARC\n";
        }
        $created_dir_or_file++;
    }
    unless (-f "$authorityserverdir/tab/sort-string-utf.chr") {
        system("cp -f $kohadir/etc/zebradb/lang_defs/fr/sort-string-utf.chr $authorityserverdir/tab/sort-string-utf.chr");
        print "Info: copied sort-string-utf.chr\n";
        $created_dir_or_file++;
    }
    unless (-f "$authorityserverdir/tab/word-phrase-utf.chr") {
        system("cp -f $kohadir/etc/zebradb/lang_defs/fr/sort-string-utf.chr $authorityserverdir/tab/word-phrase-utf.chr");
        print "Info: copied word-phase-utf.chr\n";
        $created_dir_or_file++;
    }
    unless (-f "$authorityserverdir/tab/auth1.att") {
        system("cp -f $kohadir/etc/zebradb/authorities/etc/bib1.att $authorityserverdir/tab/auth1.att");
        print "Info: copied auth1.att\n";
        $created_dir_or_file++;
    }
    unless (-f "$authorityserverdir/tab/default.idx") {
        system("cp -f $kohadir/etc/zebradb/etc/default.idx $authorityserverdir/tab/default.idx");
        print "Info: copied default.idx\n";
        $created_dir_or_file++;
    }

    unless (-f "$authorityserverdir/etc/ccl.properties") {
#         system("cp -f $kohadir/etc/zebradb/ccl.properties ".C4::Context->zebraconfig('authorityserver')->{ccl2rpn});
        system("cp -f $kohadir/etc/zebradb/ccl.properties $authorityserverdir/etc/ccl.properties");
        print "Info: copied ccl.properties\n";
        $created_dir_or_file++;
    }
    unless (-f "$authorityserverdir/etc/pqf.properties") {
#         system("cp -f $kohadir/etc/zebradb/pqf.properties ".C4::Context->zebraconfig('authorityserver')->{ccl2rpn});
        system("cp -f $kohadir/etc/zebradb/pqf.properties $authorityserverdir/etc/pqf.properties");
        print "Info: copied pqf.properties\n";
        $created_dir_or_file++;
    }

    #
    # AUTHORITIES : copying mandatory files
    #
    unless (-f C4::Context->zebraconfig('authorityserver')->{config}) {
    open my $zd, '>:encoding(UTF-8)' ,C4::Context->zebraconfig('authorityserver')->{config};
    print {$zd} "
# generated by KOHA/misc/migration_tools/rebuild_zebra.pl
profilePath:\${srcdir:-.}:$authorityserverdir/tab/:$tabdir/tab/:\${srcdir:-.}/tab/

encoding: UTF-8
# Files that describe the attribute sets supported.
attset: auth1.att
attset: explain.att
attset: gils.att

modulePath:$modulesdir/modules/
# Specify record type
iso2709.recordType:grs.marcxml.record
recordType:grs.xml
recordId: (auth1,Local-Number)
storeKeys:1
storeData:1


# Lock File Area
lockDir: $authorityserverdir/lock
perm.anonymous:r
perm.kohaadmin:rw
register: $authorityserverdir/register:4G
shadow: $authorityserverdir/shadow:4G

# Temp File area for result sets
setTmpDir: $authorityserverdir/tmp

# Temp File area for index program
keyTmpDir: $authorityserverdir/key

# Approx. Memory usage during indexing
memMax: 40M
rank:rank-1
    ";
        print "Info: creating zebra-authorities.cfg\n";
        $created_dir_or_file++;
    }

    if ($created_dir_or_file) {
        print "Info: created : $created_dir_or_file directories & files\n";
    } else {
        print "Info: file & directories OK\n";
    }

}
if ($biblios) {
    if ( $verbose_logging ) {
        print "====================\n";
        print "checking directories & files for biblios\n";
        print "====================\n";
    }

    #
    # BIBLIOS : creating directory structure
    #
    unless (-d "$biblioserverdir") {
        system("mkdir -p $biblioserverdir");
        print "Info: created $biblioserverdir\n";
        $created_dir_or_file++;
    }
    unless (-d "$biblioserverdir/lock") {
        mkdir "$biblioserverdir/lock";
        print "Info: created $biblioserverdir/lock\n";
        $created_dir_or_file++;
    }
    unless (-d "$biblioserverdir/register") {
        mkdir "$biblioserverdir/register";
        print "Info: created $biblioserverdir/register\n";
        $created_dir_or_file++;
    }
    unless (-d "$biblioserverdir/shadow") {
        mkdir "$biblioserverdir/shadow";
        print "Info: created $biblioserverdir/shadow\n";
        $created_dir_or_file++;
    }
    unless (-d "$biblioserverdir/tab") {
        mkdir "$biblioserverdir/tab";
        print "Info: created $biblioserverdir/tab\n";
        $created_dir_or_file++;
    }
    unless (-d "$biblioserverdir/key") {
        mkdir "$biblioserverdir/key";
        print "Info: created $biblioserverdir/key\n";
        $created_dir_or_file++;
    }
    unless (-d "$biblioserverdir/etc") {
        mkdir "$biblioserverdir/etc";
        print "Info: created $biblioserverdir/etc\n";
        $created_dir_or_file++;
    }

    #
    # BIBLIOS : copying mandatory files
    #
    # the record model, depending on marc flavour
    unless (-f "$biblioserverdir/tab/record.abs") {
        if (C4::Context->preference("marcflavour") eq "UNIMARC") {
            system("cp -f $kohadir/etc/zebradb/marc_defs/unimarc/biblios/record.abs $biblioserverdir/tab/record.abs");
            print "Info: copied record.abs for UNIMARC\n";
        } else {
            system("cp -f $kohadir/etc/zebradb/marc_defs/marc21/biblios/record.abs $biblioserverdir/tab/record.abs");
            print "Info: copied record.abs for USMARC\n";
        }
        $created_dir_or_file++;
    }
    unless (-f "$biblioserverdir/tab/sort-string-utf.chr") {
        system("cp -f $kohadir/etc/zebradb/lang_defs/fr/sort-string-utf.chr $biblioserverdir/tab/sort-string-utf.chr");
        print "Info: copied sort-string-utf.chr\n";
        $created_dir_or_file++;
    }
    unless (-f "$biblioserverdir/tab/word-phrase-utf.chr") {
        system("cp -f $kohadir/etc/zebradb/lang_defs/fr/sort-string-utf.chr $biblioserverdir/tab/word-phrase-utf.chr");
        print "Info: copied word-phase-utf.chr\n";
        $created_dir_or_file++;
    }
    unless (-f "$biblioserverdir/tab/bib1.att") {
        system("cp -f $kohadir/etc/zebradb/biblios/etc/bib1.att $biblioserverdir/tab/bib1.att");
        print "Info: copied bib1.att\n";
        $created_dir_or_file++;
    }
    unless (-f "$biblioserverdir/tab/default.idx") {
        system("cp -f $kohadir/etc/zebradb/etc/default.idx $biblioserverdir/tab/default.idx");
        print "Info: copied default.idx\n";
        $created_dir_or_file++;
    }
    unless (-f "$biblioserverdir/etc/ccl.properties") {
#         system("cp -f $kohadir/etc/zebradb/ccl.properties ".C4::Context->zebraconfig('biblioserver')->{ccl2rpn});
        system("cp -f $kohadir/etc/zebradb/ccl.properties $biblioserverdir/etc/ccl.properties");
        print "Info: copied ccl.properties\n";
        $created_dir_or_file++;
    }
    unless (-f "$biblioserverdir/etc/pqf.properties") {
#         system("cp -f $kohadir/etc/zebradb/pqf.properties ".C4::Context->zebraconfig('biblioserver')->{ccl2rpn});
        system("cp -f $kohadir/etc/zebradb/pqf.properties $biblioserverdir/etc/pqf.properties");
        print "Info: copied pqf.properties\n";
        $created_dir_or_file++;
    }

    #
    # BIBLIOS : copying mandatory files
    #
    unless (-f C4::Context->zebraconfig('biblioserver')->{config}) {
    open my $zd, '>:encoding(UTF-8)', C4::Context->zebraconfig('biblioserver')->{config};
    print {$zd} "
# generated by KOHA/misc/migrtion_tools/rebuild_zebra.pl
profilePath:\${srcdir:-.}:$biblioserverdir/tab/:$tabdir/tab/:\${srcdir:-.}/tab/

encoding: UTF-8
# Files that describe the attribute sets supported.
attset:bib1.att
attset:explain.att
attset:gils.att

modulePath:$modulesdir/modules/
# Specify record type
iso2709.recordType:grs.marcxml.record
recordType:grs.xml
recordId: (bib1,Local-Number)
storeKeys:1
storeData:1


# Lock File Area
lockDir: $biblioserverdir/lock
perm.anonymous:r
perm.kohaadmin:rw
register: $biblioserverdir/register:4G
shadow: $biblioserverdir/shadow:4G

# Temp File area for result sets
setTmpDir: $biblioserverdir/tmp

# Temp File area for index program
keyTmpDir: $biblioserverdir/key

# Approx. Memory usage during indexing
memMax: 40M
rank:rank-1
    ";
        print "Info: creating zebra-biblios.cfg\n";
        $created_dir_or_file++;
    }

    if ($created_dir_or_file) {
        print "Info: created : $created_dir_or_file directories & files\n";
    } else {
        print "Info: file & directories OK\n";
    }

}
}
