package App::SimpleScan::Variables;

use warnings;
use strict;
use English qw(-no_match_vars);

our $VERSION = '1.00';

use Carp;
use App::SimpleScan::TestSpec;
use Graph;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors( qw(override debug) );

################################
# Basic class methods.

# Create the object. 
# - initialize substitution dictonary: maps variables to possible values
# - initialize dependency graph: maps variables to dependencies
sub new {
  my ($class) = @_;
  my $self = {};
  $self->{Substitution_data}= {};
  $self->{Dependencies} = new Graph;
  bless $self, $class;
  return $self;
}

sub _delete_substitution {
  my ($self, $pragma_name) = @_;
  delete $self->{Substitution_data}->{$pragma_name};
  $self->{Dependencies}->delete_vertex($pragma_name);
  return;
}

sub _var_names {
  my $self = shift;
  return keys %{ $self->{Substitution_data} };
}

# If the current thing has substitutions in it,
# queue those onto the input and return true.
# Else return false.
sub _queue_var_names {
  my($self, $line) = @_;
  # Extract the variables used in this line, then look up all of 
  # their dependencies. This set of variables is the maximum number
  # of variables we'll need to worry about substituting into the line.
  #
  # This can probably be refined still more, but this at least prevents
  # us from iterating pointlessly over variables that we can't 
  # possibly substitute into the line.
  
  my @vars = $self->_all_dependencies($line =~ /(<\S+?>|>\S+?<)/g);

  # There weren't any variables to substitute. Just exit.
  return 0 unless @vars;
  
  # We've gathered up all of the possible substitutions; do them. 
  my $results = $self->_substitute($line, @vars );

  # We got multiple substitutions.
  if (@{ $results } > 1) {
    # substitutions definitely happened
    $self->queue_lines(@{ $results });
    return 1;
  }
  # Single line but different, so substitution(s) happened
  elsif ($results->[0] ne $line) {
    $self->queue_lines(@{ $results });
    return 1;
  }
  # Weird. We should never get "nothing happened" as the result 
  # of doing a substitution!
  else {
    die "Can't happen: variables to substitute, but nothing happened\n";
  }
}

# Actually do variable substitutions.
sub _substitute {

  # We get the line and all the variables we might want to substitute.
  my($self, $line, @var_names) = @_;

  my %alteration_for =();

  # Count the number of items for each substitution,
  # and calculate the maximum combination index from this.
  # of the counts of all 
  my %item_count_for;
  my $max_combination = 1;
  for my $var_name (sort @var_names) {
     $max_combination *= 
      $item_count_for{$var_name} = () = 
        $self->_substitution_value($var_name);
  }

  for my $i (0 .. $max_combination-1) {
    # Convert the combination index into a hash of
    # data indexed out of the substitution value lists.
    my %current_value_of = $self->_comb_index($i, %item_count_for);

    # Substitute the new current values into
    # the line until it stops changing, and then save
    # this line. We have to do it this way because it's possible
    # that some substituted values will actually be variable
    # references, and those will need to be resolved too.
    my $new_line = $line;
    my $line_changed = 1;
    my %change_count_for = ();
    while ($line_changed) {
      $line_changed = 0;
      for my $var_name (@var_names) {
        my $current_value = $current_value_of{$var_name};
        my $var_inserted;
        $var_inserted ||= ($new_line =~ s/>$var_name</$current_value/mxg);
        $var_inserted ||= ($new_line =~ s/<$var_name>/$current_value/mxg);
        if ($var_inserted) {
          $change_count_for{$current_value}++;
          $line_changed++;
        }
      }
    }

    # The "alteration key" is the list of *values* substituted into the line.
    # We sort the keys to prevent random key access from confusing us.
    # %change_count_for is keyed by the *values* substituted in, so 
    # we get a different substitution key for each unique set of values.
    # This makes sure we get all of the distinct possibilities and 
    # eliminate duplicates.
    my $alteration_key = "@{[sort keys %change_count_for]}";
    $alteration_for{$alteration_key} = $new_line;
  }
  return [sort values %alteration_for];
}

sub _comb_index {
  # this subroutine converts a combination index to a specific set of 
  # values, one for each of the variables in the list.
  my($self, $index, %item_counts) = @_;
  my @indexes = $self->_comb($index, %item_counts);
  my $i = 0;
  my %selection_for;
  my @ordered_keys = sort keys %item_counts;
  local $_;                                                ##no critic
  my %base_map_of = map { $_ => $i++ } @ordered_keys;
  for my $var (@ordered_keys) {
    $selection_for{$var} = 
      $self->_substitution_data($var)->[$indexes[$base_map_of{$var}]];
  }
  return %selection_for;
}

sub _comb {
  # Convert a combination index into a list of indexes into the 
  # value arrays. We don't try to look up tha values, just calculate
  # the indexes.
  my($self, $index, %item_counts) = @_;
  my @base_order = sort keys %item_counts;
  my @comb;
  my $place = 0;

  # All indexes must start at zero.
  my $number_of_items = scalar keys %item_counts;
  foreach my $item (keys %item_counts) {
    push @comb, 0;
  }

  # convert from base 10 to the derived multi-base number
  # that maps into the indexes into the possible values.
  while ($index) {
    $comb[$place] = $index % $item_counts{$base_order[$place]};
    $index = int $index/$item_counts{$base_order[$place]};
    $place++;
  }
  return @comb;
}

# setter/getter for substitution data.
# - setter needs a name and a list of values.
# - getter needs a name, returns a list of values.
sub _substitution_value {
  my ($self, $pragma_name, @pragma_values) = @_;
  if (! defined $pragma_name) {
    die 'No pragma specified';
  }
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
  if (! defined $pragma_name) {
    croak 'No pragma specified';
  }

  if (@pragma_values) {
    if (${$self->override} and 
        $self->{Predefs}->{$pragma_name}) {
      if (${$self->debug}) {
        $self->stack_code(qq(diag "Substitution $pragma_name not altered to '@pragma_values'";\n));
      }
    }
    else {
      $self->_substitution_value($pragma_name, @pragma_values);
    }
  }
  else {
    $self->_substitution_value($pragma_name);
  }
  return 
    wantarray ? @{$self->{Substitution_data}->{$pragma_name}}
              : $self->{Substitution_data}->{$pragma_name};
}

##################################
# Dependency checking

# It's necessary to make sure that the substitution pragmas
# don't have looping dependencies; these would cause the 
# input stack to grow without limit as it tries to resolve
# all of the substitutions.
#
# All we have to do is make sure that the graph of variable
# relations is a directed acyclic graph. Since actually writing
# all that would be a pain, we use Graph.pm to manage it for us.

sub _check_dependencies {
  my ($self, $var, @dependencies) = @_;
  my $graph = $self->{Dependencies};

  # drop anything that's not a variable definition.
  @dependencies = grep { /^<.*>$/mx } @dependencies;

  # No variables, no dependencies.
  if (! @dependencies) {
    return 1, 'no dependencies';
  }

  # Add the new dependencies.
  $self->_depend($var, @dependencies);
 
  # Make sure that the graph remains a DAG. If not, look for and 
  # return a cycle. Note that it's possible that there's more than one
  # cycle, though not likely, since we're checking every time we add 
  # a new variable. 
  unless ($graph->is_dag) {
    return $graph->find_a_cycle;
  }
}

# Set/get the dependencies for a given item.
sub _depend {
  my($self, $item, @dependencies) = @_;
  my $graph = $self->{PragmaDepend};

  # We used to call this with no argument to get all of the 
  # variables; we don't do that anymore because we've got a
  # better way of handling variable resolution. Drop us on
  # our heads if we try.
  if (!defined $item) {
    die "You don't want to do that anymore; use the normal variable resolution methods\n";
  }

  # Called with just a name. Get the items that are dependent on this one.
  if (!@dependencies) {
    return ([ $graph->successors($item) ]);
  }

  # Add a list of dependencies for the item.
  $graph->add_edge($item, $_) for @dependencies;    ## no critic
  return;
}

# Determine all dependencies associated with the current list of items.
sub _all_dependencies {
  my ($self, @items) = @_;

  # No dependencies; empty list.
  return () unless scalar @items; 

  # Initialize: guaranteed to not be the number of items we have now.
  my $previous_item_count = -1;
  while (1) {
    # Drop out if the item count has stopped changing.
    last if $previous_item_count == scalar @items;
    for my $item (@items) {
      # Discard any item that is not a valid variable first.
      next unless $self->{PragmaDepend}->has_vertex($item);

      # Get all the dependencies of this item.
      my @deps =  @{ $self->_depend($item) };
      foreach my $dep (@deps) {
        $accumulated{$dep} = 1;
      }
    }
  }

  # No new dependencies. Stop recursing.
  return @items if int keys %accumulated == int @items;

  # At least one new dependency.
  # Recursively call this routine to resolve any new dependencies.
  return $self->_all_dependencies(keys %accumulated);
}

1; # Magic true value required at end of module
__END__

=head1 NAME

App::SimpleScan::Substitution - simple_scan variable substitution support


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

=head1 IMPORTANT NOTE

The interfaces to this module are still evolving; plugin 
developers should monitor CPAN and look for new versions of
this module. Henceforth, any change to the externals of this
module will be denoted by a full version increase (e.g., from
0.34 to 1.00).

=head1 INTERFACE

=head2 Class methods

=head2 new 

Creates a new instance of the application. Also invokes
all of the basic setup so that when C<go> is called, all
of the plugins are available and all callbacks are in place.

=head2 Instance methods

=head3 Execution methods

=head4 go

Executes the application. Calls the subsidiary methods to
read input, parse it, do substitutions, and transform it into
code; loads the plugins and any code filters which they wish to
install.

After the code is created, it consults the command-line
switches and runs the generated program, prints it, or both.

=head4 create_tests

Transforms the input into code, and finalizes them, 
returning the actual test code (if any) to its caller.

=head2 transform_test_specs

Does all the work of transforming test specs into code,
including processing substitutions, test specs, and
pragmas, and handling substitutions.

=head2 finalize_tests

Adds all of the Perl modules required to run the tests to the 
test code generated by this module. This includes any
modules specified by plugins via the plugin's C<test_modules>
class method.

=head2 execute

Actually run the generated test code. Currently just C<eval>'s
the generated code.

=head3 Options methods

=head4 parse_command_line

Parses the command line and sets the corresponding fields in the
C<App::SimpleScan> object. See the X<EXTENDING SIMPLESCAN> section 
for more information.

=head4 handle_options

This method initializes your C<App::SimpleScan> object. It installs the
standard options (--run, --generate, and --warn), installs any
options defined by plugins, and then calls C<parse_command_line> to
actually parse the command line and set the options.

=head4 install_options(option => receiving_variable, "method_name")

Plugin method - optional.

Installs an entry into the options description passed
to C<GeOptions> when C<parse_command_line> is called. This 
automatically creates an accessor for the option.
The option description(s) should conform to the requirements 
of C<GetOpt::Long>.

You may specify as many option descriptions as you like in a 
single call. Remember that your option definitions will cause
a new method to be created for each option; be careful not to
accidentally override a pre-existing method ... unless you 
want to do that, for whatever reason.

=head4 app_defaults

Set up the default assumptions for the application. Simply 
turns C<run> on if neither C<run> nor C<generate> is specified.

=head2 Pragma methods

=head3 install_pragma_plugins

This installs the standard pragmas (C<cache>, C<nocache>, and 
C<agent>). Checks each plugin for a C<pragmas> method and
calls it to get the pragmas to be installed. In addition,
if any pragmas are found, calls the corresponding plugin's
C<init> method if it exists.

=head3 pragma

Provides access to pragma-processing code. Useful in plugins to 
get to the pragmas installed for the plugin concerned.

=head2 Input/output methods

=head3 next_line

Reads the next line of input, handling the possibility that a plugin
or substitution processing has stacked lines on the input queue to 
be read and processed (or perhaps reprocessed).

=head3 expand_backticked

Core and plugin method - a useful line-parsing utility.

Expands single-quoted, double-quoted, and backticked items in a
text string as follows:

=over 4 

=item * single-quoted: remove the quotes and use the string as-is.

=item * double-quoted: eval() the string in the current context and embed the result.

=item * backquoted: evaluate the string as a shell command and embed the output.

=back

=head3 queue_lines

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

=head3 set_current_spec

Save the object passed as the current test spec. If no 
argument is passed, deletes the current test spec object.

=head3 get_current_spec

Plugin method.

Retrieve the current test spec. Can be used to
extract data from the parsed test spec.

=head3 last_line

Plugin and core method.

Current input line setter/getter. Can be used by
plugins to look at the current line.

=head3 stack_code

Plugin and core method.

Adds code to the final output without incrementing the number of tests.
Does I<not> go through code filters, and does I<not> increment the 
test count.

=head3 stack_test

Adds code to the final output and bumps the test count by one.
The code passes through any plugin code filters.

=head3 tests

Accessor that stores the test code generated during the run.

=head1 EXTENDING SIMPLESCAN

=head2 Adding new command-line options

Plugins can add new command-line options by defining an
C<options> class method which returns a list of 
parameter/variable pairs, like those used to define 
options with C<Getopt::Long>. 

C<App::SimpleScan> will check for the C<options> method in 
your plugin when it is loaded, and call it to install your 
options automatically.

=head2 Adding new pragmas

Plugins can install new pragmas by implementing a C<pragmas>
class method. This method should return a list of array
references, with each array reference containing a 
pragma name and a code reference which will implement the
pragma.

The actual pragma implementation will, when called by
C<transform_test_specs>, receive a reference to the 
C<App::SimpleScan> object and the arguments to the pragma
(from the pragma line in the input) as a string of text. It is
up to the pragma to parse the string; the use of 
C<expand_backticked> is recommended for pragmas which 
take a variable number of arguments, and wish to adhere
to the same syntax that standard substitutions use.

=head1 PLUGIN SUMMARY

Standard plugin methods that App::SimpleScan will look for;
none of these is required, though you should choose to
implement the ones that you actually need.

=head2 Basic callbacks

=head3 init

The C<init> class method is called by C<App:SimpleScan>
when the plugin class is loaded; the C<App::SimpleScan>
object is suppled to allow the plugin to alter or add to the
contents of the object. This allows plugins to export methods
to the base class, or to add instance variables dynamically.

Note that the class passed in to this method is the class
of the I<plugin>, not of the caller (C<App::SimpleScan>
or a derived class). You should use C<caller()> if you wish
to export subroutines into the package corresponding to the 
base class object.

=head3 pragmas

Defines any pragmas that this plugin implements. Returns a 
list of names and subroutine references. These will be called
with a reference to the C<App::SimpleScan> object.

=head3 filters

Defines any code filters that this plugin wants to add to the
output filter queue. These methods are called with a copy
of the App::SimpleScan object and an array of code that is 
about to be stacked. The filter should return an array 
containing either the unaltered code, or the code with any
changes the plugin sees fit to make.

If your filter wants to stack tests, it should call 
C<stack_code> and increment the test count itself (by
a call to test_count); trying to use C<stack_test> in 
a filter will cause it to be called again and again in
an infinite recursive loop.

=head3 test_modules

If your plugin generates code that requires other Perl modules,
its test_modules class method should return an array of the names
of these modules.

=head3 options

Defines options to be added to the command-line options.
You should return an array of items that would be suitable
for passing to C<Getopt::Long>, which is what we'll do 
with them.

=head3 validate_options

Validate your options. You can access any of the variables
you passed to C<options>; these will be initialized with 
whatever values C<Getopt::Long> got from the command line.
You should try to ignore invalid values and choose defaults 
for missing items if possible; if not, you should C<die>
with an appropriate message.

=head2 Methods to alter the input stream

=head3 next_line

If a plugin wishes to read the input stream for its own
purposes, it may do so by using C<next_line>. This returns
either a string or undef (at end of file). 

=head3 stack_input

Adds lines to the input queue ahead of the next line to 
be read from whatever source is supplying them. This allows
your plugin to process a line into multiple lines "in place".

=head2 Methods for outputting code

Your pragma will probably use one of the following methods to 
output code:

=head3 stack_code

A call to C<stack_code> will cause the string passed back to 
be emitted immediately into the code stream. The test count
will remain at its current value. 

=head3 stack_test

C<stack_test> will immediately emit the code supplied as
its argument, and will increment the test count by one. You
should use multiple calls to C<stack_test> if you need
to stack more than one test. 

Code passed to stack_test will go through all of the 
filters in the output filter queue; be careful to not
call C<stack_test> in an output filter, as this will
cause a recursive loop that will run you out of memory.

=head2 Informational methods

=head2 get_current_spec

Returns the current App::SimpleScan::TestSpec 
object, if there is one. If code in your plugin is
called when either we haven't read any lines yet,
or the last line read was a pragma, there won't be
any "current test spec".

=head2 last_line

Returns the actual text of the previous line read.
Plugin code that does not specifically involve the
current line (like output filters) may wish to look
at the current line.

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
