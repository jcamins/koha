#!/usr/bin/perl 

use strict;
use CGI;
use Template;
use JSON;
use C4::Biblio;
use C4::AuthoritiesMarc;

my $cgi = CGI->new();
my $op = $cgi->param('op');
my $key = $cgi->param('key');
my $typecode = $cgi->param('typecode');

print $cgi->header('application/json');

if ($op eq 'authorize') {
    my ( $results, $total ) = SearchAuthorities( ['mainmainentry'], [], [], ['contains'], [$key], 0, 20, $typecode, 'HeadingAsc');

    my $json->{'headings'} = $results;
    print to_json($json);
}
#use Data::Dumper; warn Data::Dumper::Dumper(@$results);
