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

=item * whether or not it should be there

=item * and a comment about why you care

=back

=head2 Matching non-ASCII Latin-1 characters

First: be sure that the non-ASCII character you're seeing on the screen is actually
present in the HTML source. You could be looking at an HTML entity that gets rendered
as the character in question. For instance a degree symbol is actually C<&xB0;>. 

You can match a specific entity with its actual text:

  /&x[bB]0;/

(Note that we've made sure that it will work whether the hex "digits" are upper or
lowercase.) Or you can match an arbitrary entity:

  /&.*?;/

This one will also match things like C<&amp;> and C<&brkbar;> - with great power
comes relative imprecision. There's a handy table of Latin-1 entities at
L<http://www.ramsch.org/martin/uni/fmi-hp/iso8859-1.html>.

In some cases (e.g., Yahoo!'s fr.search search results), there will actually be
non-Latin1 characters that are not HTML encoded. This is probably not good 
practice, but it still exists here and there. To deal with pages like this,
copy and paste the exact text from a "view source" into the regex you want 
to use. C<simple_scan> will try to spot all of the non-ASCII characters and
add special tests for them.

=over 4

Note to advanced regex wielders: using capturing parentheses along with
non-Latin characters will cause test failures if the capturing parens
appear in the pattern before the non-ASCII character(s). This is because 
the pattern transformation needed to accurately match the non-ASCII
characters requires that we replaced them with capturing parentheses
to, well, capture the non-ASCII characters and test them directly with
C<eq>. If you add your own capturing parentheses before the non-ASCII
characters, you throw the capture off, and the comparison will fail.

So: either break the test up into multiple parts, with the parens you
add to the pattern in one part and the non-ASCII characters in another,
or use non-capturing parentheses for grouping:

  (?:foo|bar|baz)

This allows you to group alternatives without capturing anything, thus
keeping C<simple_scan>'s head on straight when it comes to non-ASCII characters.

=back

The best solution? Find the developer concerned and have a chat about
encoding entities. 

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
