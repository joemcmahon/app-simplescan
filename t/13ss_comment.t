#!/usr/local/bin/perl
use Test::More tests=>1;
use Test::Differences;

@output = `bin/simple_scan<examples/ss_comment.in`;
@expected = map {"$_\n"} split /\n/,<<EOF;
1..1
ok 1 - Perl.org available [http://perl.org/] [/perl/ should match]
EOF
eq_or_diff(\@output, \@expected, "working output as expected");
