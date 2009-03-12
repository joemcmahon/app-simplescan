package App::SimpleScan;

our $VERSION = '0.01';
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

use base qw(Class::Accessor::Fast);

sub new {
  my ($class) = @_;
  my $self = {};
  $self->{Substitution_data}= {};
  bless $self, $class;
  App::SimpleScan::TestSpec->app($self);
  $self->tests([]);
  $self->_substitution_data("agent", "Windows IE 6");
  binmode(STDIN);

  return $self;
}

sub create_tests {
  my ($self) = @_;

  $self->test_count(0);
  $self->tests([]);

  $self->handle_options;
  $self->install_pragma_plugins;
  $self->transform_test_specs;
  $self->finalize_tests;
  return join("", @{$self->tests});
}

sub go {
  my($self) = @_;
  my $exit_code = 0;

  my $code = $self->create_tests;
  # Note the dereference of the scalars here.

  if ($self->test_count) {
    eval $code if ${$self->run};
    if ($@) {
       warn $@,"\n";
       $exit_code = 1;
    }
  } 
  else {
    if (${$self->warn}) {
      warn "# No tests were found in your input file.\n";
      $exit_code = 1;
    }
  }

  print $code,"\n" if ${$self->generate};

  return $exit_code;
}

sub transform_test_specs {
  my ($self) = @_;
  local $_;
  while(<>) {
    chomp;
    # Discard comments.
    /^#/ and next;

    # Discard blank lines.
    /^\s*$/ and next;

    # Handle pragmas.
    /^%%\s*(.*?)(((:\s+|\s+)(.*)$)|$)/ and do {
      if (my $code = $self->_pragma($1)) {
        $code->($self,$5);
      }
      else {
        # It's a substitution if it has no other meaning.
        my @data = split /\s+/, $5 if defined $5;
        $self->_substitution_data($1, @data);
      }
      next;
    };

    my $item = App::SimpleScan::TestSpec->new($_);
    if ($item->syntax_error) {
      $self->tests([
                    @{$self->tests},
                    "# ".$item->raw."\n",
                    "# Possible syntax error in this test spec\n",
                   ]) if ${$self->warn};
                     
    }
    else {
      my @generated = $item->as_tests;
      $self->tests([@{$self->tests}, @generated]);
      $self->test_count($self->test_count+(int @generated));
    }
  }
}

sub _substitutions {
  my ($self) = @_;
  keys %{$self->{Substitution_data}} 
    if defined $self->{Substitution_data};
}

sub _substitution_data {
  my ($self, $pragma_name, @pragma_values) = @_;
  die "No pragma specified" unless defined $pragma_name;
  if (@pragma_values) {
    $self->{Substitution_data}->{$pragma_name} = \@pragma_values;
  }
  wantarray ? @{$self->{Substitution_data}->{$pragma_name}}
            : $self->{Substitution_data}->{$pragma_name};
}

sub handle_options {
  my ($self) = @_;

  # Variables and setup for basic command-line options.
  my($generate, $run, $warn);

  my %basic_options = 
    ('generate' => \$generate,
     'run'      => \$run,
     'warn'     => \$warn);

  # Handle options, including ones from the plugins.
  $self->install_options(%basic_options);

  foreach my $plugin (__PACKAGE__->plugins) {
    $self->install_options($plugin->options)
      if $plugin->can(qw(options));
  }
  $self->parse_command_line;
  $self->app_defaults;
}

sub app_defaults {
  my ($self) = @_;
  # Assume run if no flags at all.
  return if defined ${$self->generate()};
  $self->run(\1);
}

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
    $self->{Options}->{$option} = $receiver;

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

sub parse_command_line {
  my ($self) = @_;
  GetOptions(%{$self->{Options}});
}

sub install_pragma_plugins {
  my ($self) = @_;

  foreach my $plugin (@local_pragma_support, 
                      __PACKAGE__->plugins) {
     if (ref $plugin eq 'ARRAY') {
       $self->_pragma(@$plugin);
     }
     else {
       eval "use $plugin";
       $@ and die "Plugin $plugin failed to load: $@\n";
       foreach my $pragma_spec ($plugin->pragmas) {
         $self->_pragma(@$pragma_spec);
       }
     }
  }
}

sub _pragma {
  my ($self, $name, $pragma) = @_;
  die "You forgot the pragma name\n" if ! defined $name;
  $self->{Pragma}->{$name} = $pragma
    if defined $pragma;
  $self->{Pragma}->{$name};
}

sub _do_agent {
  my ($self, $rest) = @_;
  $rest = reverse $rest;
  my ($maybe_agent) = ($rest =~/^\s*(.*)$/);
  
  $maybe_agent = reverse $maybe_agent; 
  $self->_substitution_data("agent", $maybe_agent)
    if grep { $_ eq $maybe_agent } $reference_mech->known_agent_aliases;
  $self->_stack_code(qq(user_agent("$maybe_agent");\n));
}

sub _do_cache {
  my ($self,$rest) = @_;
  $self->_stack_code("cache();\n");
}

sub _do_nocache {
  my ($self,$rest) = @_;
  $self->_stack_code("no_cache();\n");
}

sub _stack_code {
  my ($self, @code) = @_;
  my @old_code = @{$self->tests};
  $self->tests([@old_code, @code]);
}

sub _stack_test {
  my($self, @code) = @_;
  $self->_stack_code(@code);
  $self->test_count($self->test_count()+1);
}

sub finalize_tests {
  my ($self) = @_;
  my @tests = @{$self->tests};
  foreach my $plugin (__PACKAGE__->plugins) {
    my @modules = $plugin->test_modules if $plugin->can('test_modules');
    unshift @tests, "use $_;\n" foreach @modules;
  }
  unshift @tests, 
    (
      "use Test::More tests=>" . $self->test_count . ";\n",
      "use Test::WWW::Simple;\n",
    );
  $self->tests([@tests]);
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

=head2 finalize_tests

Adds all of the Perl modules required to run the tests to the 
test code generated by this module. 

=head2 tests

Accessor that stores the test code generated during the run.

=head1 EXTENDING SIMPLESCAN

=head2 Adding new command-line options

Plugins can add new command-line options by defining an
C<options> class method which returns a set of parameters
appropriate for C<install_options>. C<App::SimpleScan> will
check for this method when you plugin is loaded, and call 
it to install your options automatically.

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