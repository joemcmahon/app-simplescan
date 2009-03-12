use Test::More tests=>4;

BEGIN {
  use_ok qw(App::SimpleScan);
  use_ok qw(App::SimpleScan::TestSpec);
}

my $ss = new App::SimpleScan;
ok $ss->can('plugins'), "plugins method available";
isa_ok [$ss->plugins()],"ARRAY", "returns right thing";
