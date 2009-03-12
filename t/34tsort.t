use Test::More;
use Test::Differences;

BEGIN {
  use_ok qw(App::SimpleScan);
}

my $app = new App::SimpleScan;

my @tests = (
  [ [qw(a b)],             # No cycles
    [qw(b c d)],
    [qw(c e)],
    [1, 'd e c b a'] ],
  [ [qw(a b)],             # a b cycle
    [qw(b a)],
    [0, 'a b'] ],
  [],                      # drop all data
  [ [qw(d e)],             # x y z cycle
    [qw(e f)],
    [qw(a b)],
    [qw(b c)],
    [qw(g h)],
    [qw(x y)],
    [qw(y z)],
    [qw(z x)],
    [0, 'x y z'] ],
);
plan tests=>(int @tests)-1;

for my $test (@tests) {
  # empty set resets all dependencies
  if (! int @$test) {
    $app->{PragmaDepend} = {};
    next;
  }

  my @expected = @{ pop @$test };
  
  for my $insert (@$test) {
    $app->_depend(@$insert);
  }
  my (@result) = $app->_tsort();
  eq_or_diff(\@result, \@expected, "tsort works");
}
  
