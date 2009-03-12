#!/usr/local/bin/perl
use Test::More tests=>4;
use Test::Differences;
use App::SimpleScan;
use IO::ScalarArray;

$ENV{HARNESS_PERL_SWITCHES} = "" unless defined $ENV{HARNESS_PERL_SWITCHES};

@output = `$^X $ENV{HARNESS_PERL_SWITCHES} -Iblib/lib bin/simple_scan --gen --warn <examples/ss_garbage1.in`;
@expected = map {"$_\n"} split /\n/,<<EOF;
use Test::More tests=>0;
use Test::WWW::Simple;
use strict;

mech->agent_alias('Windows IE 6');
# This is a file of garbage.
# Possible syntax error in this test spec
# None of this is a valid test.
# Possible syntax error in this test spec
# All of it will be skipped.
# Possible syntax error in this test spec
# No tests will be generated.
# Possible syntax error in this test spec

EOF
push @expected, "\n";
eq_or_diff(\@output, \@expected, "working output as expected");

@ARGV=qw(examples/ss_garbage2.in);
$app = new App::SimpleScan;
@output = map {"$_\n"} (split /\n/, ($app->create_tests));
@expected = map {"$_\n"} split /\n/,<<EOF;
use Test::More tests=>1;
use Test::WWW::Simple;
use strict;

mech->agent_alias('Windows IE 6');
page_like "http://perl.org/",
          qr/perl/,
          qq(Garbage lines were ignored [http://perl.org/] [/perl/ should match]);

EOF
eq_or_diff(\@output, \@expected, "output as expected");

@output = `bin/simple_scan<examples/ss_garbage2.in`;
@expected = map {"$_\n"} split /\n/,<<EOF;
1..1
ok 1 - Garbage lines were ignored [http://perl.org/] [/perl/ should match]
EOF
eq_or_diff(\@output, \@expected, "ran as expected");

@output = `bin/simple_scan --gen --warn<examples/ss_garbage3.in`;
@expected = map {"$_\n"} split /\n/,<<EOF;
use Test::More tests=>1;
use Test::WWW::Simple;
use strict;

mech->agent_alias('Windows IE 6');
# 'this line has a 
# This line has an unmatched quote of some kind and was skipped.
# Subsequent lines may have a problem if this was because of a newline.
# line break in it'
# Possible syntax error in this test spec
page_unlike "http://perl.org",
            qr/this line has a  /,
            qq(Demo the linebreak message [http://perl.org] [/this line has a  / shouldn't match]);

EOF
push @expected, "\n";
eq_or_diff(\@output, \@expected, "output as expected");
