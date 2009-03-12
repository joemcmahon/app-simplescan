use Test::More tests => 2;

BEGIN {
use_ok( 'App::SimpleScan' );
}

my $app = new App::SimpleScan;
can_ok $app, qw(new go transform_test_specs
                _substitutions _substitution_data
                handle_options app_defaults
                install_options parse_command_line 
                install_pragma_plugins
                _pragma  _do_agent _stack_code _stack_test
                finalize_tests );
