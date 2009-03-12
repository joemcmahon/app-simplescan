use Test::More tests=>13;
use Test::Differences;

BEGIN {
  use_ok(qw(App::SimpleScan));
  use_ok(qw(App::SimpleScan::TestSpec));
}

can_ok("App::SimpleScan::TestSpec", qw(uri delim kind regex comment new as_tests app parse metaquote));

my $app = new App::SimpleScan;
App::SimpleScan::TestSpec->app($app);

my $raw = "http://search.yahoo.com/ /yahoo/ Y No comment";
my $spec = new App::SimpleScan::TestSpec($raw);
is $spec->app, $app, "Specs can find the app";
is $spec->raw, $raw, "Raw spec available";

$spec->parse;

$spec->uri("http://search.yahoo.com");
$spec->delim('/');
$spec->comment('No comment');
$spec->regex("yahoo");

is ($spec->uri, "http://search.yahoo.com", "uri accessor");
is ($spec->delim, "/", "delim accessor");
is ($spec->comment, "No comment", "comment accessor");
is ($spec->regex, "yahoo", "regex accessor");

$spec->kind('Y');
$expected = <<EOS;
page_like "http://search.yahoo.com",
          qr/yahoo/,
          "No comment [http://search.yahoo.com] [/yahoo/ should match]";
EOS
eq_or_diff [split /\n/,($spec->as_tests)[0]], [split /\n/, $expected], "Y works";

$spec->kind('N');
$expected = <<EOS;
page_unlike "http://search.yahoo.com",
            qr/yahoo/,
            "No comment [http://search.yahoo.com] [/yahoo/ shouldn't match]";
EOS
eq_or_diff [split /\n/, ($spec->as_tests)[0]], [split /\n/, $expected], "N works";

$spec->kind('TY');
$expected = <<EOS;
TODO: {
  local \$TODO = 'Doesn't match now but should later';
  page_like "http://search.yahoo.com",
            qr/yahoo/,
            "No comment [http://search.yahoo.com] [/yahoo/ should match]";
}
EOS
eq_or_diff [split /\n/, ($spec->as_tests)[0]], [split /\n/, $expected], "TY works";

$spec->kind('TN');
$expected = <<EOS;
TODO: {
  local \$TODO = 'Matches now but shouldn't later';
  page_unlike "http://search.yahoo.com",
              qr/yahoo/,
              "No comment [http://search.yahoo.com] [/yahoo/ shouldn't match]";
}
EOS
eq_or_diff [split /\n/, ($spec->as_tests)[0]], [split /\n/, $expected], "TN works";