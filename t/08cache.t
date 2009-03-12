use Test::More tests=>4;
use Test::Differences;

my @output = `echo "%%cache" |bin/simple_scan --gen`;
ok((scalar @output), "got output");
my $expected = <<EOS;
use Test::More tests=>0;
use Test::WWW::Simple;
cache();

EOS
eq_or_diff(join("",@output), $expected, "output matches");

@output = `echo "%%nocache" |bin/simple_scan --gen`;
ok((scalar @output), "got output");
$expected = <<EOS;
use Test::More tests=>0;
use Test::WWW::Simple;
no_cache();

EOS
eq_or_diff(join("",@output), $expected, "output matches");


