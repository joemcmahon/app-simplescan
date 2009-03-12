#!/usr/local/bin/perl
use Test::More tests=>1;
use Test::Differences;

@output = `bin/simple_scan<examples/ss_user_agent.in`;
@expected = map {"$_\n"} split /\n/,<<EOF;
1..3
ok 1 - Perl should be there (Windows IE 6) [http://perl.org/] [/perl/ should match]
ok 2 - Perl should be there (Mac Safari) [http://perl.org/] [/perl/ should match]
ok 3 - Perl should be there (Linux Konqueror) [http://perl.org/] [/perl/ should match]
EOF
eq_or_diff(\@output, \@expected, "working output as expected");
