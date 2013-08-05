#!/usr/bin/perl
# derived from http://wiki.koha-community.org/wiki/Plack#opac.psgi
# Copyright Chris Hall and Catalyst

use Plack::Builder;
use Plack::App::CGIBin;
use Plack::App::Directory;

use lib("/usr/share/koha/lib");
use C4::Context;
use C4::Languages;
use C4::Members;
use C4::Dates;
use C4::Boolean;
use C4::Letters;
use C4::Koha;
use C4::XSLT;
use C4::Branch;
use C4::Category;
use Module::Load::Conditional qw(check_install);

C4::Context->disable_syspref_cache();

my $app=Plack::App::CGIBin->new(root => "/usr/share/koha/opac/cgi-bin/opac");

builder {
# leave static files to apache/nginx
#        enable "Plack::Middleware::Static",
#                path => qr{^/opac-tmpl/}, root => '/srv/koha/koha-tmpl/';
#                path => qr{^/opac-tmpl/}, root => '/usr/share/koha/opac/htdocs/';

        enable 'StackTrace';
        if ( check_install( module => 'Plack::Middleware::ReverseProxy' ) ) {
            enable_if { !defined( $_[0]->{REMOTE_ADDR} ) } "ReverseProxy";
        }

        mount "/cgi-bin/koha" => $app;
};
