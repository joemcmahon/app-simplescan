=head1 NAME

App::SimpleScan::Cookbook

=head1 DESCRIPTION

This is a documentation-only module that describes how to use C<simple_scan>
for some common Web testing problems.

=head1 BASICS

C<simple_scan> reads I<test specifications> from standard input and generates
Perl code based on these specifications. It can either

=over 4

=item * execute them immediately,

=item * print them on standard output without executing them,

=item * or do both: execute them and then print the generated code on standard output.

=back

=head1 TEST SPECS

Test specifications describe

=over 4

=item * I<where> the page is that you want to check,

=item * some I<content> (in the form of a Perl regular expression) that you want look for

=item * 

=back

=head1 PLUGINS

Plugins are Perl modules that extend C<simple_scan>'s abilities without modification
of the core code.

=head2 Installing a new pragma

Create a C<pragmas> method in your plugin that returns pairs of pragma names and
methods to be called to process the pragma.

  sub pragmas {
    return (['mypragma' => \&do_my_pragma],
            ['another'  => \&another]);
  }

  sub do_my_pragma {
    my ($app, $args);
    # Parse the arguments. You have access to
    # all of the methods in App::SimpleScan as
    # well as any subs defined here. You may 
    # want to export methods to the App::SimpleScan
    # namespace in your import() method.
  }

  ...

=head2 Installing new command-line options

Create an C<options> method in your plugin that returns a hash of options and
variables to capture their values in. You will also want to export accessors
for these variables to the C<App::SimpleScan> namespace in your C<import>.

  sub import {
    no strict 'refs';
    *{caller() . '::myoption} = \&myoption;
  }

  sub options {
    return ('myoption' => \$myoption);
  }

  sub myoption {
    my ($self, $value) = @_;
    $myoption = $value if defined $value;
    $myoption;
  }

=head2 Installing other modules via plugins

Create a C<test_modules> method that returns a list of module names
to be C<use>d by the generated test program.

  sub test_modules {
    return ('Test::Foo', 'Blortch::Zonk');
  }

=head2 Adding extra code to the test output stack in a plugin

Create a C<per_test> subroutine. This method gets called with the
current C<App::SimpleScan::TestSpec> object.

  sub per_test {
    $self->app->_stack_test(qw(fail "forced failure accessing bad.com";\n))
     if $self->uri =~ /bad.com/;
  }
