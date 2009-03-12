use Test::More tests=>5;
use Test::Exception;

BEGIN {
  use_ok(qw(App::SimpleScan));
  use_ok(qw(App::SimpleScan::TestSpec));
}

my $app = new App::SimpleScan;


$app->_substitution_data('foo', 'bar');
$app->_substitution_data('bar', 'baz', 'quux');

my $spec = App::SimpleScan::TestSpec->new("http://<foo>.com /bar/ Y Match 'bar'");
$spec->app($app);

my $result = $spec->_substitute([$spec->raw], sort $app->_substitutions);
is_deeply $result, ["http://bar.com /bar/ Y Match 'bar'"], "single substitute";

$spec = App::SimpleScan::TestSpec->new("http://<bar>.com /bar/ Y Match 'bar'");
$spec->app($app);

$result = $spec->_substitute([$spec->raw], sort $app->_substitutions);
is_deeply $result, ["http://baz.com /bar/ Y Match 'bar'",
                    "http://quux.com /bar/ Y Match 'bar'"], "foo unchanged";

$app->_substitution_data('foo', 'bar', 'baz');
$spec = App::SimpleScan::TestSpec->new("http://<foo>.com /<bar>/ NS Match '<bar>'");
$spec->app($app);
$result = $spec->_substitute([$spec->raw], sort $app->_substitutions);
is_deeply $result, ["http://bar.com /baz/ NS Match 'baz'",
                    "http://bar.com /quux/ NS Match 'quux'",
                    "http://baz.com /baz/ NS Match 'baz'",
                    "http://baz.com /quux/ NS Match 'quux'"],
                    'both changed';


