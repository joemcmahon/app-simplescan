#!/usr/local/bin/perl
use Test::More tests=>7;
use Test::Differences;

$ENV{HARNESS_PERL_SWITCHES} = "" unless defined $ENV{HARNESS_PERL_SWITCHES};

@output = `$^X $ENV{HARNESS_PERL_SWITCHES} -Iblib/lib bin/simple_scan<examples/ss_fail.in 2>tmp.out`;
@expected = map {"$_\n"} split /\n/,<<EOF;
1..4
not ok 1 - No python on perl.org [http://perl.org/] [/python/ should match]
not ok 2 - No perl on python.org [http://python.org/] [/perl/ should match]
not ok 3 - Python on python.org [http://python.org/] [/python/ shouldn't match]
not ok 4 - Perl on perl.org [http://perl.org/] [/perl/ shouldn't match]
EOF
eq_or_diff(\@output, \@expected, "failed STDOUT as expected");

open(PRODUCED_STDERR, "tmp.out") or die "Can't open saved STDERR: $!\n";
@output = <PRODUCED_STDERR>;
@expected = map {"$_\n"} split /\n/, <<EOF;

#     Failed test (/home/y/lib/perl5/site_perl/5.6.1/Test/WWW/Simple.pm at line 36)
#          got: "\x{0a}<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Tran"...
#       length: 8294
#     doesn't match '(?-xism:python)'

#     Failed test (/home/y/lib/perl5/site_perl/5.6.1/Test/WWW/Simple.pm at line 36)
#          got: "<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Trans"...
#       length: 11516
#     doesn't match '(?-xism:perl)'

#     Failed test (/home/y/lib/perl5/site_perl/5.6.1/Test/WWW/Simple.pm at line 43)
#          got: "<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Trans"...
#       length: 11516
#           matches '(?-xism:python)'
#     Failed test (/home/y/lib/perl5/site_perl/5.6.1/Test/WWW/Simple.pm at line 43)

#          got: "\x{0a}<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Tran"...
#       length: 8256
#           matches '(?-xism:perl)'
# Looks like you failed 4 tests of 4.
EOF

is($expected[-1], $output[-1], "summary right");
is int(grep {/Failed/} @output), 4, "right number of failures";
is int(grep {/got:/} @output), 4, "right number of 'got' lines";
is int(grep {/length: /} @output), 4, "right number of 'length' lines";
is int(grep {/doesn't match '\(\?-xism:/} @output), 2, "right number of 'doesn't match' lines";
is int (grep {/matches '\(\?-xism:/} @output), 2, "right number of 'matches' lines";
unlink "tmp.out";
