#!/usr/local/bin/perl
use Test::More tests=>1;
use Test::Differences;

@output = `echo "http://yahoo.com/ /Yahoo/ Y branding" | bin/simple_scan --gen --autocache`;
@expected = map {"$_\n"} split /\n/,<<EOF;
use Test::More tests=>1;
use Test::WWW::Simple;
use strict;

my \@accent;
cache;
page_like "http://yahoo.com/",
          qr/Yahoo/,
          qq(branding [http://yahoo.com/] [/Yahoo/ should match]);


EOF
push @expected,"\n";
eq_or_diff(\@output, \@expected, "working output as expected");
