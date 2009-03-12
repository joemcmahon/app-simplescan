package App::SimpleScan;

our $VERSION = '0.32';
use 5.006;

use warnings;
use strict;
use Carp;

use Getopt::Long;
use Regexp::Common;
use Scalar::Util qw(blessed);
use WWW::Mechanize;
use WWW::Mechanize::Pluggable;
use Test::WWW::Simple;
use App::SimpleScan::TestSpec;
use Text::Balanced qw(extract_quotelike extract_multiple);

my $reference_mech = new WWW::Mechanize::Pluggable;

use Module::Pluggable earch_path => [qw(App::SimpleScan::Plugin)];

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(tests test_count));

use App::SimpleScan::TestSpec;

my @local_pragma_support =
  (
    ['agent'   => \&_do_agent],
    ['nocache'   => \&_do_nocache],
    ['cache'   => \&_do_cache],
  );

# Variables and setup for basic command-line options.
my($generate, $run, $warn, $override, $defer, $debug);
my($cache_from_cmdline, $no_agent);

# Option-to-variable mappings for Getopt::Long
my %basic_options = 
  ('generate'  => \$generate,
   'run'       => \$run,
   'warn'      => \$warn,
   'override'  => \$override,
   'defer'     => \$defer,
   'debug'     => \$debug,
   'autocache' => \$cache_from_cmdline,
   'no-agent'  => \$no_agent,
  );

use base qw(Class::Accessor::Fast);

# Create the object. 
# - load and install plugins
# - make object available to test specs for callbacks
# - clear the tests and test count
# - process the command-line options
# - return the object
sub new {
  my ($class) = @_;
  my $self = {};
  $self->{Substitution_data}= {};
  bless $self, $class;
  $self->_load_plugins();

  $self->install_pragma_plugins;

  App::SimpleScan::TestSpec->app($self);

  $self->tests([]);
  $self->test_count(0);
  $self->{InputQueue} = [];
  $self->{PragmaDepend} = {};

  binmode(STDIN);

  $self->handle_options;

  return $self;
}

# Read the test specs and turn them into tests.
# Add any additional code from the plugins.
# Return the tests as a string.
sub create_tests {
  my ($self) = @_;

  $self->transform_test_specs;
  $self->finalize_tests;
  return join("", @{$self->tests});
}

# If the tests should be run, run them.
# Return any exceptions to the caller.
sub execute {
  my ($self, $code) = @_;
  eval $code if ${$self->run};
  return $@;
}

# Actually use the object.
# - create tests from input
# - run them if we should
# - print them if we should
sub go {
  my($self) = @_;
  my $exit_code = 0;

  my $code = $self->create_tests;
  # Note the dereference of the scalars here.

  if ($self->test_count) {
    if (my $result = $self->execute($code)) {
       warn $result,"\n";
       $exit_code = 1;
    }
  } 
  else {
    if (${$self->warn}) {
      $self->stack_test(qq(fail "No tests were found in your input file.\n"));
      $exit_code = 1;
    }
  }

  print $code,"\n" if ${$self->generate};

  return $exit_code;
}

# Read files from command line or standard input.
# Turn these from test specs into test code.
sub transform_test_specs {
  my ($self) = @_;
  local $_;
  while(defined( $_ = $self->next_line )) {
    chomp;
    # Discard comments.
    /^#/ and next;

    # Discard blank lines.
    /^\s*$/ and next;

    # Handle pragmas.
    /^%%\s*(.*?)(((:\s+|\s+)(.*)$)|$)/ and do {
      if (my $code = $self->pragma($1)) {
        $code->($self,$5);
      }
      else {
        # It's a substitution if it has no other meaning.
        if (defined($5)) {
          my $var = $1;
          my @data = _expand_backticked($5);
          my ($status, $message) = $self->_check_dependencies($var, @data);
          if ($status) {
            $self->_substitution_data($var, @data);
          }
          else {
            my @items = split $message;
            my $between = (@items < 3) ? "between" : "among";
            $self->stack_test( qw(fail "Cannot add substitution for $var: dependency loop $between $message";\n));
          }
        }
      }
      next;
    };

    # Commit any substitutions.
    # We use 'next' because the substituted lines
    # will have been queued on the input if there
    # where any substitutions.
    #
    # We do this *after* pragma processing because 
    # if we have this:
    #  %%foo bar baz
    #  %%quux <foo> is the value
    #
    # and we expanded pragmas in place, we'd get
    #  %%foo bar baz
    #  %%quux bar
    #  %%quux baz
    #
    # which is probably *not* what is wanted.
    # Putting this here makes sure that we only
    # substitute into actual test specs.
    next if $self->_queue_substitutions($_);

    # No substitutions in this line, so just process it.
    my $item = App::SimpleScan::TestSpec->new($_);

    # Store it in case a plugin needs to look at the 
    # test spec in an overriding method.
    $self->set_current_spec($item);

    if ($item->syntax_error) {
      $self->tests([
                    @{$self->tests},
                    "# ".$item->raw."\n",
                    "# Possible syntax error in this test spec\n",
                   ]) if ${$self->warn};
                     
    }
    else {
      $item->as_tests;
    }
    # Drop the spec (there isn't one active now).
    $self->set_current_spec();
  }
}

# Handle backticked values in substitutions.
sub _expand_backticked {
  my ($text) = shift;

  # Extract strings and backticked strings and just plain words.
  my @data;
  {
    # extract_quotelike complains if no quotelike strings were found.
    # Shut this up.
    no warnings;

    # The result of the extract multiple is to give us the whitespace
    # between words and strings with leading whitespace before the
    # first word of quotelike strings. Confused? This is what happens:
    #
    # for the string
    #   a test `backquoted' "just quoted"
    # we get
    #   'a'
    #   ' '
    #  'test'
    #  ' `backquoted'
    #  `backquoted`
    #  ' '
    #  ' "just'
    #  '"just quoted"'
    #
    # The grep removes all the strings starting with whitespace, leaving
    # only the things we actually want.
    @data = grep { /^\s/ ? () : $_ } 
            extract_multiple($text, [qr/[^'"`\s]+/,\&extract_quotelike]);
  
  } 

  local $_;
  my @result;
  for (@data) {
    # eval a backticked string and split it the same way.
    if (/^`(.*)$`/) {
      push @result, _expand_backticked(eval $_);
    }
    # Double-quoted: eval it.
    elsif (/^"(.*)"$/) {
      push @result, eval($1);
    }
    # Single-quoted: remove quotes.
    elsif (/^'(.*)'$/) {
      push @result, $1;
    }
    # Not quoted at all: leave alone
    else {
      push @result, $_;
    }
  }
  return @result;
}

sub set_current_spec {
  my ($self, $testspec) = @_;
  $self->{CurrentTestSpec} = $testspec;
}

sub get_current_spec {
  my ($self) = @_;
  return $self->{CurrentTestSpec};
}


sub _delete_substitution {
  my ($self, $pragma_name) = @_;
  delete $self->{Substitution_data}->{$pragma_name};
  return;
}

# Get all active substitutions.
sub _substitutions {
  my ($self) = @_;
  keys %{$self->{Substitution_data}} 
    if defined $self->{Substitution_data};
}

# If the current thing has substitutions in it,
# queue those onto the input and return true.
# Else return false.
sub _queue_substitutions {
  my($self, $line) = @_;
  my $results = $self->_substitute([$line], $self->_substitutions);
  if (@$results != 1) {
    # substitutions definitely happened
    $self->queue_lines(@$results);
    return 1;
  }
  elsif ($results->[0] ne $line) {
    # single line is different, so substitution(s) happened
    $self->queue_lines(@$results);
    return 1;
  }
  else {
    # nothing happened, just process it as is
    return 0;
  }
}

# Actually do variable substitutions.
sub _substitute {
  my($self, $tests_ref, @var_names) = @_;
 
  # Haven't bottomed out yet. Save one to
  # do and pass rest to recursion. Don't
  # recurse if this is the last one.
  my $mine;
  ($mine, @var_names) = @var_names;

  $tests_ref = $self->_substitute($tests_ref, @var_names)
    if @var_names;

  # Handle the current substitution over the tests we
  # currently have.
  my @results;
  my $original;
  my $changed;

  foreach my $test (@$tests_ref) {
    # Save the original (in case there are no substitutions).
    $original = $test;

    foreach my $value ($self->_substitution_data($mine)) {
      # Restore the unsubstituted version.
      $test = $original;

      # No changes made yet.
      $changed = 0;

      # change it if we need to and remember we did.
      $changed ||= ($test =~ s/<$mine>/$value/g);
      $changed ||= ($test =~ s/>$mine</$value/g);

      # Save it if we changed it.
      if ($changed) {
        push @results, $test;
      }

      # Don't keep trying to substitute if we didn't
      # change anything.
      else {
        last;
      }
    }

    # Push the unchanged version if there was nothing
    # to change.
    unless ($changed) {
      push @results, $original;
    }
  }

  # Return whatever we've generated, either up one
  # level of the recursion, or to the original caller.
  return \@results;
}

# setter/getter for substitution data.
# - setter needs a name and a list of values.
# - getter needs a name, returns a list of values.
sub _do_substitution {
  my ($self, $pragma_name, @pragma_values) = @_;
  die "No pragma specified" unless defined $pragma_name;
  if (@pragma_values) {
    $self->{Substitution_data}->{$pragma_name} = \@pragma_values;
  }
  return 
    wantarray ? @{$self->{Substitution_data}->{$pragma_name}}
              : $self->{Substitution_data}->{$pragma_name};
}

# Wrapper function for setter/getter that implements the
# override function (command-line substitutions override 
# substitutions in the input).
sub _substitution_data {
  my ($self, $pragma_name, @pragma_values) = @_;
  croak "No pragma specified" unless defined $pragma_name;

  if (@pragma_values) {
    if (${$self->override} and $self->{Predefs}->{$pragma_name}) {
      $self->stack_code(qq(diag "Substitution $pragma_name not altered to '@pragma_values'";\n))
        if ${$self->debug};
    }
    else {
      $self->_do_substitution($pragma_name, @pragma_values);
    }
  }
  else {
    $self->_do_substitution($pragma_name);
  }
  return 
    wantarray ? @{$self->{Substitution_data}->{$pragma_name}}
              : $self->{Substitution_data}->{$pragma_name};
}

sub handle_options {
  my ($self) = @_;

  # Handle options, including ones from the plugins.
  $self->install_options(%basic_options);

  # The --define option has to be handled slightly differently.
  # We set things up so that we have a hash of predefined variables
  # in the object; that way, we can set them up appropriately, and
  # know whether or not they should be checked for override/defer
  # when a definition is found in the simple_scan input file.
  $self->{Options}->{'define=s%'} = ($self->{Predefs} = {});

  foreach my $plugin (__PACKAGE__->plugins) {
    $self->install_options($plugin->options)
      if $plugin->can('options');
  }

  $self->parse_command_line;

  foreach my $plugin (__PACKAGE__->plugins) {
    $plugin->validate_options($self) if
      $plugin->can('validate_options');
  }

  # If anything was predefined, save it in the substitutions.
  for my $def (keys %{$self->{Predefs}}) {
    $self->_do_substitution($def, 
                            (split /\s+/, $self->{Predefs}->{$def}));
  }

  if (${$self->no_agent}) {
    $self->_do_substitution("agent", "WWW::Mechanize::Pluggable");
  }
  else {
    $self->_do_substitution("agent", "Windows IE 6");
    $self->stack_code("mech->agent_alias('Windows IE 6');\n");
  }
  
  $self->app_defaults;
}

# Set up application defaults.
sub app_defaults {
  my ($self) = @_;
  # Assume --run if neither --run nor --generate.
  if (!defined ${$self->generate()} and
      !defined ${$self->run()}) {
    $self->run(\1);
  }

  # Assume --defer if neither --defer nor --override.
  if (!defined ${$self->defer()} and
      !defined ${$self->override()}) {
    $self->defer(\1);
  }

  # if --cache was supplied, turn caching on.
  $self->stack_code(qq(cache;\n))
    if ${$self->autocache};
}

# Transform the options specs (whether from here or
# from plugins) into methods that we can call to
# set/get the option values.
sub install_options {
  my ($self, @options) = @_;
  $self->{Options} = {} unless defined $self->{Options};

  # precompilation versions of the possible methods. These
  # get compiled right when we need them, causing $option
  # to be capturd as a closure.

  while (@options) {
    # This coding is deliberate.
    #
    # We want a separate copy of $option and 
    # $receiver each time; we don't want a new
    # copy of @options, because we want to keep
    # effectively shifting two values off each
    # time around the loop.
    #
    # Note that the generated method returns a 
    # reference to the variable that the option is
    # stored into; this makes it simpler to code
    # the accessor here. If you use an array or
    # hash to receive values in your Getopt spec,
    # you'll have to dereference it properly in
    # your code.
    (my($option, $receiver), @options) = @options;

    # Method names containing dashes are a no-no;
    # swap them to underscores. (This is okay because
    # no one outside this module should be trying to
    # call these methods directly.)
    $option =~ s/-/_/g;

    $self->{Options}->{$option} = $receiver;

    # Ensure that the variables have been cleared if we create another
    # App::SimpleScan object (normally we won't, but our tests do).
    $$receiver = undef;

    # Create method if it doesn't exist.
    unless ($self->can($option)) {
      no strict 'refs';
      *{'App::SimpleScan::'.$option} = 
        sub { 
              my ($self, $value) = @_;
              $self->{Options}->{$option} = $value if defined $value;
              $self->{Options}->{$option};
            };
    }
  }
}

# Load all the plugins.
sub _load_plugins {
  my($self) = @_;
  foreach my $plugin (__PACKAGE__->plugins) {
    eval "use $plugin";
    $@ and die "Plugin $plugin failed to load: $@\n";
  }
}

# Call Getopt::Long to parse the command line.
sub parse_command_line {
  my ($self) = @_;
  GetOptions(%{$self->{Options}});
}

# Install any pragmas supplied by plugins.
# We reuse this same code to install all of
# the locally defined pragmas.
sub install_pragma_plugins {
  my ($self) = @_;

  foreach my $plugin (@local_pragma_support, 
                      __PACKAGE__->plugins) {
    if (ref $plugin eq 'ARRAY') {
      $self->pragma(@$plugin);
    }
    elsif ($plugin->can('pragmas')) {
      foreach my $pragma_spec ($plugin->pragmas) {
        $self->pragma(@$pragma_spec);
        if ($plugin->can('init')) {
          $plugin->init($self);
        }
      }
    }
  }
}

# Find the pragma code associated with the name.
sub pragma {
  my ($self, $name, $pragma) = @_;
  die "You forgot the pragma name\n" if ! defined $name;
  $self->{Pragma}->{$name} = $pragma
    if defined $pragma;
  $self->{Pragma}->{$name};
}

# %%agent pragma handler. Verify that the argument
# is a valid WW::Mechanize agent alias string, and
# stack code to change it as appropriate.
sub _do_agent {
  my ($self, $rest) = @_;
  $rest = reverse $rest;
  my ($maybe_agent) = ($rest =~/^\s*(.*)$/);
  
  $maybe_agent = reverse $maybe_agent; 
  $self->_substitution_data("agent", $maybe_agent)
    if grep { $_ eq $maybe_agent } $reference_mech->known_agent_aliases;
  $self->stack_code(qq(user_agent("$maybe_agent");\n));
}

# %%cache - turn on Test::WWW::Simple's cache.
sub _do_cache {
  my ($self,$rest) = @_;
  $self->stack_code("cache();\n");
}

# %%nocache - turn off Test::WWW::Simple's cache.
sub _do_nocache {
  my ($self,$rest) = @_;
  $self->stack_code("no_cache();\n");
}

# Handle input queueing. If there's anything queued,
# return it first; otherwise, just read another line
# from the magic input filehandle.
sub next_line {
  my ($self) = shift;
  my $next_line;
  if (defined $self->{InputQueue}->[0] ) {
    $next_line = shift @{ $self->{InputQueue} };
  }
  else {
    $next_line = <>;
  }
  return $next_line;
}

# Handle input stacking by pragmas. Add any new lines
# to the head of the queue.
sub queue_lines {
  my ($self, @lines) = @_;
  $self->{InputQueue} = [ @lines, @{ $self->{InputQueue} } ];
}

# stack_code just adds code to the array holding
# the generated program.
sub stack_code {
  my ($self, @code) = @_;
  my @old_code = @{$self->tests};
  $self->tests([@old_code, @code]);
}

# stack_test adds code to the array holding
# the generated program, and bumps the test
# count so we can use the proper number of tests
# in our test plan.
sub stack_test {
  my($self, @code) = @_;
  $self->stack_code(@code);
  $self->test_count($self->test_count()+1);
}

# Calls each plugin's test_modules method
# to stack any other test modules needed to
# properly handle the test code. (Plugins may
# want to generate test code that needs 
# something like Test::Differences, etc. - 
# this lets them load that module so the
# tests actually work.)
#
# Also adds the test plan and the array we use
# to capture accented characters (we should be
# able to dump this kludge soon...)
#
# Finally, initializes the user agent (unless
# we're specifically directed *not* to do so).
sub finalize_tests {
  my ($self) = @_;
  my @tests = @{$self->tests};
  my @prepends;
  foreach my $plugin (__PACKAGE__->plugins) {
    my @modules = $plugin->test_modules if $plugin->can('test_modules');
    push @prepends, "use $_;\n" foreach @modules;
  }
  unshift @prepends, 
    (
      "use Test::More tests=>" . $self->test_count . ";\n",
      "use Test::WWW::Simple;\n",
      "use strict;\n",
      "\n",
      "my \@accent;\n",
    );
  
  # Handle conditional user agent initialization.
  # This was added because some servers (e.g., WAP
  # servers) refuse connections from known user agents,
  # but others (e.g., Yahoo!'s web servers) refuse 
  # login attempts from non-browser user agents.
  #
  # Set the user agent unless --no-agent was given.

  if (!$self->no_agent) {
    push @prepends, qq(mech->agent_alias("Windows IE 6");\n);
  }
  
  
  $self->tests( [ @prepends, @tests ] );
}

### Dependencies
# It's necessary to make sure that the substitution pragmas
# don't have looping dependencies; these would cause the 
# input stack to grow without limit as it tries to resolve
# all of the substitutions.
#
# We use a topological sort of the dependencies to make 
# sure that the there are no loops in the substitution
# pragma dependencies. This is a sort that takes as its
# input a definition of the order that the items are 
# supposed to occur in, and returns either an ordering
# of the data, or a list of the items that are mutually
# dependent.

sub _check_dependencies {
  return 1, "dummied out";
}

sub _depend {
  my($self, $item, @parents) = @_;
  if (!defined $item) {
    return keys %{ $self->{PragmaDepend} };
  }

  if (!@parents) {
    return ($self->{PragmaDepend}->{$item} or []);
  }

  for my $parent (@parents) {
    push @{ $self->{PragmaDepend}->{$parent} }, $item;
  }
}

sub _tsort {
  my $self = shift;

  my %pairs;	# all pairs ($l, $r)
  my %npred;	# number of predecessors
  my %succ;	# list of successors

  for my $parent ($self->_depend) {
    for my $child (@{ $self->_depend($parent) }) {
      next if defined $pairs{$parent}{$child};
      $pairs{$parent}{$child}++;
      $npred{$parent} += 0;
      ++$npred{$child};
      push @{$succ{$parent}}, $child;
    }
  }

  # create a list of nodes without predecessors
  my @list = grep { ! $npred{$_} } keys %npred;

  my @order;
  while (@list) {
    push @order, ($_ = pop @list);
    foreach my $child (@{$succ{$_}}) {
      unshift @list, $child unless --$npred{$child};
    }
  }

  $self->{DependencyOrder} = \@order;

  my @looped;
  for (keys %npred) {
    push @looped, $_ if $npred{$_};
  }
  @looped ? return(0, "@looped")
          : return(1, "@order");
}

1; # Magic true value required at end of module
__END__

=head1 NAME

App::SimpleScan - simple_scan's core code


=head1 VERSION

This document describes App::SimpleScan version 0.0.1


=head1 SYNOPSIS

    use App::SimpleScan;
    my $app = new App::SimpleScan;
    $app->go;
    

  
=head1 DESCRIPTION

C<App::SimpleScan> allows us to package the core of C<simple_scan>
as a class; most importantly, this allows us to use C<Module::Pluggable>
to write extensions to this application without directly modifying
this module or this C<simple_scan> application.

=head1 INTERFACE

=head2 new 

Creates a new instance of the application.

=head2 create_tests

Reads the test input and expands the tests into actual code.

=head2 go

Executes the application. Calls C<create_test> to handle the
actual test creation.

=head2 handle_options

This method initializes your C<App::SimpleScan> object. It installs the
standard options (--run, --generate, and --warn), installs any
options defined by plugins, and then calls C<parse_command_line> to
actually parse the command line and set the options.

=head2 install_options(option => receiving_variable, "method_name")

Installs an entry into the options description passed
to C<GeOptions> when C<parse_command_line> is called. This 
automatically creates an accessor for the option.
The option description(s) should conform to the requirements 
of C<GetOpt::Long>.

You may specify as many option descriptions as you like ina 
single call. Remember that your option definitions will cause
a new method to be created for each option; be careful not to
accidentally override a pre-existing method.

=head2 parse_command_line

Parses the command line and sets the corresponding fields in the
C<App::SimpleScan> object. See the X<EXTENDING SIMPLESCAN> section 
for more information.

=head2 app_defaults

Set up the default assumptions for the application. The base method
simply turns C<run> on if neither C<run> nor C<generate> is specified.

=head2 install_pragma_plugins

This installs the standard pragmas (C<cache>, C<nocache>, and 
C<agent>) and any supplied by the plugins.

=head2 transform_test_specs

Does all the work of transforming test specs into code.

=head2 next_line

Reads the next line of input, handling the possibility that a plugin 
has stacked lines on the input queue to be read and processed (or
perhaps reprocessed).

=head2 queue_lines

Queues one or more lines of input ahead of the current "next line".

If no lines have been queued yet, simply adds the lines to the input
queue. If there are existing lines in the input queue, lines passed
to this routine are queued I<ahead> of those lines, like this:

  # Input queue = ()
  # $app->queue_lines("save this")
  #
  # Input queue now = ("save this")
  # $app->queue_lines("this one", "another")
  #
  # input queue now = ("this one", "another", "save this")

This is done so that if a pragma queues lines which are other pragmas,
these get processed before any other pending input does.

=head2 set_current_spec

Save the argument passed as the current test spec. If no 
argument is passed, sets the current spec to undef.

=head2 get_current_spec

Retrieve the current test spec. 

=head2 stack_code

Adds code to the final output without incrementing the number of tests.

=head2 stack_test

Adds code to the final output and bumps the test count by one.

=head2 pragma

Provides access to pragma-processing code. Useful in plugins to 
get to the pragmas installed for the plugin concerned.

=head2 finalize_tests

Adds all of the Perl modules required to run the tests to the 
test code generated by this module. 

=head2 tests

Accessor that stores the test code generated during the run.

=head2 execute

Actually run the generated test code. Currently just C<eval>'s
the generated code.

=head1 EXTENDING SIMPLESCAN

=head2 Adding new command-line options

Plugins can add new command-line options by defining an
C<options> class method which returns a set of parameters
appropriate for C<install_options>. C<App::SimpleScan> will
check for this method when you plugin is loaded, and call 
it to install your options automatically.

=head2 Adding new pragmas

Plugins can install new pragmas by implementing a C<pragmas>
class method. This method should return a list of array
references, with each array reference containing a 
pragma name and a code reference which will implement the
pragma.

The actual pragma implementation will receive a reference to
the C<App::SimpleScan> object and the arguments to the pragma
(from the pragma line in the input) as a string of text. It is
up to the pragma to parse the string.

Pragma will probably use one of the following methods to 
output test code:

=over 4

=item * init

The C<init> class method is called by C<App:SimpleScan>
when the plugin class is loaded; the C<App::SimpleScan>
object is suppled to allow the plugin to alter or add to the
contents of the object. This allows plugins to export methods
to the base class, or to add instance variables dynamically.

Note that the class passed in to this method is the class
of the I<plugin>, not of the caller (C<App::SimpleScan>
or a derived class). You should use C<caller()> if you wish
to export subroutines into the class corresponding to the 
base class object.

=item * stack_code("code to stack")

A call to C<stack_code> will cause the string passed back to 
be emitted immediately into the code stream. The test count
will remain at its current value.

=item * stack_test("code and tests to stack")

C<stack_test> will immediately emit the code supplied as
its argument, and will increment the test count by one. You
should use multiple calls to C<stack_test> if you need
to stack more than one test.

=item * per_test()

If a pragma wants to stack code that will be emitted for
every test, it should implement a  C<per_test> method.
This will be called by C<App::SimpleScan::TestSpec> for
every testspec processed.

Code to be emitted I<before> the current test should
be emitted via calls to C<stack_code> and C<stack_test>.

Code to be emitted I<after> the current test should be
I<returned> to the caller, along with a count indicating 
how many tests are included in the returned code. You
can return zero to indicate that none of the returned
code is tests.

=back

=head1 DIAGNOSTICS

None as yet.

=head1 CONFIGURATION AND ENVIRONMENT

App::SimpleScan requires no configuration files or environment variables.

=head1 DEPENDENCIES

Module::Pluggable and WWW::Mechanize::Pluggable.

=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-app-simplescan@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Joe McMahon  C<< <mcmahon@yahoo-inc.com > >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2005, Joe McMahon C<< <mcmahon@yahoo-inc.com > >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
