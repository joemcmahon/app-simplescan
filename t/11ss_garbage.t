#!/usr/local/bin/perl
use Test::More tests=>3;
use Test::Differences;
use App::SimpleScan;
use IO::ScalarArray;

my $app = new App::SimpleScan;
@ARGV=qw(--warn examples/ss_garbage1.in);
my @output = map {"$_\n"} (split /\n/, ($app->create_tests));

@expected = map {"$_\n"} split /\n/,<<EOF;
use Test::More tests=>0;
use Test::WWW::Simple;
# This is a file of garbage.
# Possible syntax error in this test spec
# None of this is a valid test.
# Possible syntax error in this test spec
# All of it will be skipped.
# Possible syntax error in this test spec
# No tests will be generated.
# Possible syntax error in this test spec

EOF
eq_or_diff(\@output, \@expected, "working output as expected");

@ARGV=qw(examples/ss_garbage2.in);
$app = new App::SimpleScan;
@output = map {"$_\n"} (split /\n/, ($app->create_tests));
@expected = map {"$_\n"} split /\n/,<<EOF;
use Test::More tests=>1;
use Test::WWW::Simple;
page_like "http://perl.org/",
          qr/perl/,
          "Garbage lines were ignored [http://perl.org/] [/perl/ should match]";

EOF
eq_or_diff(\@output, \@expected, "output as expected");

@output = `bin/simple_scan<examples/ss_garbage2.in`;
@expected = map {"$_\n"} split /\n/,<<EOF;
1..1
ok 1 - Garbage lines were ignored [http://perl.org/] [/perl/ should match]
EOF
eq_or_diff(\@output, \@expected, "ran as expected");
