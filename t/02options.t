use Test::More tests=>7;

BEGIN {
  use_ok(qw(App::SimpleScan));
}

my $app = new App::SimpleScan;
is $app->{Options}, undef, "No options when first created";
my $foo;
$app->install_options(foo=>\$foo);
can_ok $app, qw(foo);
isa_ok $app->{Options}, "HASH", "hash there now";
is_deeply $app->{Options}, {foo=>\$foo}, "right thing";
@ARGV = qw(--foo);
$app->parse_command_line();
is ${$app->foo}, 1, "set value";
is $foo, 1, "got into our variable";
