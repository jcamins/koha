#!/usr/bin/perl

BEGIN {
    $ENV{'KOHA_CONF'} = '__KOHA_CONF_DIR__/koha-conf.xml';
    $ENV{'DEBUG'} = 1;
}

use lib("__PERL_MODULE_DIR__");
use lib("__PERL_MODULE_DIR__/installer");
use Plack::Builder;
use Plack::App::CGIBin;
use Plack::Middleware::Debug;
use Plack::App::URLMap;
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

C4::Context->disable_syspref_cache();

my $koha = Plack::App::CGIBin->new(root => "/home/jcamins/kohaclone");

builder {
    enable 'Debug',  panels => [
        qw(Environment Response Timer Memory),
#               'Profiler::NYTProf', # FIXME this should work, but is missing .gif exclude
#        [ 'Profiler::NYTProf',
#            exclude => [qw(.*\.css .*\.png .*\.ico .*\.js .*\.gif)],
#            base_URL => '/nytprof',
#            root => '/home/jcamins/kohaclone/koha-tmpl/nytprof',
#            minimal => 1 ],
#               [ 'DBITrace', level => 1 ],
        ];

#    enable "Plack::Middleware::Static";

    enable 'StackTrace';

    mount '/cgi-bin/koha' => $koha;
};


