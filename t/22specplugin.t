use Test::More tests=>5;

BEGIN {
  use_ok qw(App::SimpleScan);
  use_ok qw(App::SimpleScan::TestSpec);
  push @INC, "t";
}

my $ss = new App::SimpleScan;
ok $ss->can('plugins'), "plugins method available";
isa_ok [$ss->plugins()],"ARRAY", "returns right thing";
ok grep { /TestExpand/ } $ss->plugins, "test plugin there";
