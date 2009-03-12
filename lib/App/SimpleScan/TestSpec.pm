package App::SimpleScan::TestSpec;
use base qw(Class::Accessor::Fast);
use Regexp::Common;
use bytes;

use strict;

our $VERSION = "0.17";

__PACKAGE__->mk_accessors(qw(raw uri regex delim kind comment metaquote syntax_error accented flags test_count));

my $app;     # Will store a reference to the parent App::Simplescan

my %test_type = 
  (
    'Y' => <<EOS,
page_like "<uri>",
          qr<delim><regex><delim><flags>,
          "<comment> [<uri>] [<delim><regex><delim><flags> should match]";
EOS
    'N' => <<EOS,
page_unlike "<uri>",
            qr<delim><regex><delim><flags>,
            "<comment> [<uri>] [<delim><regex><delim><flags> shouldn't match]";
EOS
    'TY' => <<EOS,
TODO: {
  local \$Test::WWW::Simple::TODO = "Doesn't match now but should later";
  page_like "<uri>",
            qr<delim><regex><delim><flags>,
            "<comment> [<uri>] [<delim><regex><delim><flags> should match]";
}
EOS
    'TN' => <<EOS,
TODO: {
  local \$Test::WWW::Simple::TODO = "Matches now but shouldn't later";
  page_unlike "<uri>",
              qr<delim><regex><delim><flags>,
              "<comment> [<uri>] [<delim><regex><delim><flags> shouldn't match]";
}
EOS
    'SY' => <<EOS,
SKIP: {
  skip 'Deliberately skipping test that should match', 1; 
  page_like "<uri>",
            qr<delim><regex><delim><flags>,
            "<comment> [<uri>] [<delim><regex><delim><flags> should match]";
}
EOS
    'SN' => <<EOS,
SKIP: {
  skip "Deliberately skipping test that shouldn't match", 1; 
  page_unlike "<uri>",
              qr<delim><regex><delim><flags>,
              "<comment> [<uri>] [<delim><regex><delim><flags> shouldn't match]";
}
EOS
  );

sub app {
  my ($class_or_object, $appref) = @_;
  $app = $appref if defined $appref;
  return $app;
}

sub new {
  my ($class, $spec) = @_;
  my $self = {};
  bless $self, $class;

  # Store the test spec.
  $self->raw($spec);
  $self->accented({});
  $self->test_count(0);
  $self->syntax_error(!$self->parse);

  return $self;
}

sub parse {
  my ($self, $line) = @_;
  $line = $self->raw unless defined $line;
  chomp $line;

  # Originally, we used Regex::Common to parse the URI and regex
  # off the test spec line, but that's not going to work now since
  # we've switched to keeping the text substitutions in place
  # until we're ready to expand the spec into tests.
  #
  # So we'll do it like this: remove everything up to the first 
  # set of whitespace and call it the URI. *Reverse* the string, 
  # and match everything up to the whitespace before the kind of 
  # test; this grabs off the comment and the kind.
  #
  # We treat whatever is left at this point as the regex, in
  # three phases. First, is it a standard slash-delimited 
  # regex? If not, is it an m-style regex (m| ...|, with
  # arbitrary quote characters)? If not, then we treat it as
  # a literal string to match (stripping off the slashes on
  # either end if they are there.
  
  # Remove URI portion.
  my ($URI, $rest) = ($line =~ /^(.*?)\s+(.*)$/);
  my $copy = $URI;

  # Is this possibly a good URI?
  if (defined $copy) {
    $copy =~ s/<.*?>/foo/g;
    $copy =~ s/>.*?</foo/g;

    # No. 
    return 0 if !($copy =~ /$RE{URI}/);
  }
  else {
   # No URI there at all.
   return 0;
  }

  # Remove comment and kind.
  my ($comment, undef, $kind, $maybe_regex) = 
    ((scalar reverse $rest) =~ /^(.*?)(\s+|\s*)\b(Y|N|YT|NT|YS|NS)\s+(.*)$/);
  $self->comment(scalar reverse $comment);
  $self->kind(scalar reverse $kind);
  $self->uri($URI);

  my($clean, $delim, $flags); 

  # Clean up regex if needed.
  my $regex = reverse $maybe_regex;
  if ((undef, undef, $clean, undef, $flags) = 
       ($regex =~ m|^$RE{delimited}{-delim=>'/'}{-keep}([ics]*)$|)) {
    # Standard slash-delimited regex.
    $self->regex($clean);
    $self->delim("/");
    $self->flags($flags);
  }
  elsif (($delim, $clean, $flags) = ($regex =~ /^m(.)(.*)\1([ics]*)$/)) {
    # m-something-regex-something pattern.
    $self->delim($1);
    $self->regex($clean);
    $self->flags($flags);
  }
  elsif (($clean, $flags) = ($regex =~ m|^/(.*)/([ics]*)$|)) {
    $self->delim("/");
    $self->regex($clean);
    $self->metaquote(1);
    $self->flags($flags);
  }
  else {
    $self->delim("/");
    $self->regex($regex);
    $self->metaquote(1);
  }
  $self->flags("") unless defined $self->flags;

  # Handle accented chars if any.
  my $match_var = "0";
  my %accents;
  $regex = $self->regex();
  while (my($accented) = ($regex =~ /([\x80-\xff])/)) {
    $regex =~ s/[\x80-\xff]/(.|..)/;
    $accents{$match_var++} = $accented;
  }
  $self->accented(\%accents);
  $self->regex($regex) if keys %accents;

  # If we got this far, it's valid.
  return 1;
}

sub _render_regex {
  my ($self) = shift;
  my $uri   = $self->uri;
  my $regex = $self->regex;
  my $delim = $self->delim;
  my $flags = $self->flags;
  if (!defined $flags) {
    $self->flags("");
    $flags = "";
  }

  if ($self->metaquote) {
    $regex = "\\Q$regex\\E";
  }
  if ($delim ne "/") {
    $regex = "m$delim$regex$delim";
  }
  else {
    $regex = "/$regex/";
  }
  if ($flags) {
    $regex .= $flags;
  }

  return $regex;
}

sub as_tests {
  my ($self) = @_;
  my @tests;
  my $current = 0;
  my $flags = $self->flags() || "";
  my $uri = $self->uri;

  my %accents = %{$self->accented};
  if (defined $uri and
      defined (my $regex =   $self->regex) and
      defined (my $delim =   $self->delim) and
      defined (my $comment = $self->comment)) {
    if (defined ($tests[$current] = $test_type{$self->kind})) {
       $self->test_count($self->test_count()+1);
       $tests[$current] =~ s/<uri>/$uri/g;
       $tests[$current] =~ s/<delim>/$delim/g;
       if ($self->metaquote) {
         $tests[$current] =~ s/<regex>/\Q$regex\E/g;
       }
       else {
         $tests[$current] =~ s/<regex>/$regex/g;
       }
       $tests[$current] =~ s/<flags>/$flags/g;
       $tests[$current] =~ s/<comment>/$comment/;
       if (keys %accents) {
         push @tests, qq(\@accent = (mech->content =~ @{[$self->_render_regex]});\n);
         for my $accent (keys %accents) {
           # Keys are which variable we should expect the 
           # accented character in; values are the expected
           # character.
           push @tests, qq[is \$accent[$accent], "] . $accents{$accent} .
                        qq[", "Accent char $accent as expected";\n];
           $self->test_count($self->test_count()+1);
         }
       }
    }
  }


  # Make any variable substitutions
  my $current_in_tests = int @tests;
  my @generated = @{$self->_substitute([@tests], $self->app->_substitutions)};
  $self->test_count($self->test_count()+(scalar @generated - scalar @tests));

  # Call any plugin per_test routines.
  my @merged;
  for my $test_code (@generated) {
    push @merged, $test_code;
    for my $plugin ($app->plugins) {
      push @merged, 
        $plugin->per_test($self)
          if $plugin->can('per_test');
    }
  }
  return $self->test_count(),@merged;
}

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
  my $app = $self->app;
  my $original;
  my $changed;

  foreach my $test (@$tests_ref) {
    # Save the original (in case there are no substitutions).
    $original = $test;

    foreach my $value ($app->_substitution_data($mine)) {
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
      

1; # Magic true value required at end of module
__END__

=head1 NAME

App::SimpleScan::TestSpec - store a test spec, and transform it into test code


=head1 VERSION

This document describes App::SimpleScan::TestSpec version 0.01


=head1 SYNOPSIS

    use App::SimpleScan:TestSpec;
    App::SimpleScan::TestSpec->app($app_simplescan_object);
    my $spec = App::SimpleScan::TestSpec->new($test_spec_line);

    # Fetch the (raw) URI portion of the test spec.
    my $uri  = $spec->uri();

    # Fetch the (raw) regex portion of the spec.
    my $regex = $spec->regex();

    # Fetch the regex delimiter.
    my $delim = $spec->delim;

    # Fetch the kind of test this is.
    my $delim = $spec->kind;

    # Fetch the comment.
    my $comment = $spec->comment();

    # Expand the test spec into test code, performing all substitutions.
    my @tests = $spec->expand();
  
=head1 DESCRIPTION

C<App::SimpleScan::TestSpec> centralizes the parsing to test specifications and 
their transformation into code.

=head1 INTERFACE

=head2 app 

Accessor for the owning App::SimpleScan object. Must be called
before C<as_tests> is used to permit access to any substitution
pragma data.

=head2 new($test_spec)

Creates a new C<TestSpec> object from a test specification line.
Actually just extracts the appropriate data and prepares for
later substitutions and assembly by C<as_tests>.

=head2 raw

Returns the raw test spec text was originally passed in.

=head2 parse

Breaks up the raw line into the proper fields and 
sets the regex delimiter appropriately.

Since we're parsing a line which may or may not have 
substitution tokens in it, we have to break it on appropriate
whitespace rather than by matching a "real" URI and a "real" regex. 

=head2 uri

Accessor for the raw URI portion of the test spec.

=head2 delim

Accessor for the regex delimiter.

=head2 regex

Accessor for the regular expression itself.

=head2 kind 

Accessor for the kind of test:

=over 4

=item * Y

Pattern should match.

=item * N

Pattern should I<not> match.

=item * TY

Pattern does not match currently, but should when code is working properly (TODO).

=item * TN

Pattern matches right now, but shouldn't when code is working properly (TODO).

=item * SY

This test should be skipped; later, it should match.

=item * SN

This test should be skipped; later, it should I<not> match.

=back

=head2 as_tests

Expands the test spec into one or more lines of Perl test code.
Uses the C<app()> method to access the pragma substitution data
to expand any substitutions in the line.

=head1 EXTENDING APP::SIMPLESCAN

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
