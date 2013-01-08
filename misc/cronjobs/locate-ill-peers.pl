#!/usr/bin/perl

use strict;
use warnings;
use Net::DNS;
use Getopt::Long;
use Pod::Usage;
use C4::Context;

sub usage {
    pod2usage( -verbose => 2 );
    exit;
}

my $verbose   = 0;
my $want_help = 0;
my $timeout   = 60;
my $add_local = 1;

my $result = GetOptions(
    'v|verbose' => \$verbose,
    'h|help'    => \$want_help,
    'local!'    => \$add_local,
    't|timeout' => \$timeout,
);

binmode( STDOUT, ":utf8" );

if ( not $result or $want_help ) {
    usage();
}

my @domains = @ARGV;

push @domains, 'local' if $add_local;

die "A domain must be specified" unless @domains;

my $res = Net::DNS::Resolver->new(
    'tcp_timeout' => $timeout,
    'udp_timeout' => $timeout
);
my $query;

my %servers;

foreach my $domain (@domains) {
    print "Querying for SRV records in _koha._tcp.$domain\n" if $verbose;
    $query = $res->search( "_koha._tcp.$domain", 'SRV' );
    if ($query) {
        my @answers = $query->answer;

        foreach my $rr (@answers) {
            print "Adding peer " . $rr->target . " from $domain domain\n" if $verbose;
            $servers{ $rr->target } = {
                'domain'   => $domain,
                'priority' => $rr->priority,
                'weight'   => $rr->weight,
                'port'     => ( $rr->port || 80 )
            };
        }
    }
}

my $dbh = C4::Context->dbh;

if ($dbh) {
    eval {
        local $dbh->{PrintError} = 0;
        local $dbh->{RaiseError} = 1;
        $dbh->do(qq{SELECT * FROM ill_peers WHERE 1 = 0 });
    };
    if ($@) {
        $dbh->do(
            q{
              CREATE TABLE ill_peers (
              host VARCHAR(64) NOT NULL,
              domain VARCHAR(64),
              priority INT,
              weight INT,
              port INT DEFAULT '80',
              PRIMARY KEY (host),
              KEY (domain)
              ) ENGINE=InnoDB DEFAULT CHARSET=utf8;
              }
        );
    }
    else {
        $dbh->do("DELETE FROM ill_peers;");
    }

    my $sth = $dbh->prepare(
"INSERT INTO ill_peers (host, domain, priority, weight, port) VALUES (?, ?, ?, ?, ?)"
    );
    foreach my $host ( keys %servers ) {
        $sth->execute(
            $host,
            $servers{$host}->{'domain'},
            $servers{$host}->{'priority'},
            $servers{$host}->{'weight'},
            $servers{$host}->{'port'}
        );
    }
}
else {
    warn
"Unable to connect to Koha. Dumping server information for your edification.";
    warn Data::Dumper::Dumper( \%servers );
}

=head1 NAME

locate-ill-peers.pl

=head1 SYNOPSIS

  locate-ill-peers.pl koha-community.org
  locate-ill-peers.pl -v koha-community.org

=head1 DESCRIPTION

This cron job searches for peers in the specified domain and puts their
information in the ill_peers table in the Koha database.

=head1 OPTIONS

=over 8

=item --verbose, -v

Print verbose logging information.

=item --help, -h

Print this help.

=item --local, --no-local

Enable or disable the automatic inclusion of the .local domain. Defaults to
including .local.

=item --timeout, -t

Set timeout on DNS queries. Defaults to 60 seconds.

=back

=head1 AUTHOR

Jared Camins-Esakov, C & P Bibliography Services <jcamins@cpbibliography.com>

=cut
