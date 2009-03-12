use Test::More tests=>6;
use Test::Differences;

BEGIN {
  use_ok qw(App::SimpleScan);
}

my $app = new App::SimpleScan;
$app->_depend(qw(a b));
$app->_depend(qw(b c));
$app->_depend(qw(b d));
$app->_depend(qw(c e));

eq_or_diff([sort $app->_all_dependencies('a')],
           [qw(a b c d e)],
           'Top of tree gets all');

eq_or_diff([sort $app->_all_dependencies('b')],
           [qw(b c d e)],
           'Top of tree gets all');

eq_or_diff([sort $app->_all_dependencies('c')],
           [qw(c e)],
           'Top of tree gets all');

eq_or_diff([sort $app->_all_dependencies('d')],
           [qw(d)],
           'Top of tree gets all');

eq_or_diff([sort $app->_all_dependencies('e')],
           [qw(e)],
           'Top of tree gets all');
