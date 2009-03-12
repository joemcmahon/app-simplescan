use Test::More tests=>4;

$ENV{HARNESS_PERL_SWITCHES} = "" unless defined $ENV{HARNESS_PERL_SWITCHES};

my @output = `$^X $ENV{HARNESS_PERL_SWITCHES} -Iblib/lib bin/simple_scan <examples/ss_nodouble.in`;
ok @output, "got output"; 
is @output, 6, "No loop over non-substituted line";

@output = `$^X $ENV{HARNESS_PERL_SWITCHES} -Iblib/lib bin/simple_scan --gen <examples/ss_multisub.in`;
ok @output, "got output"; 
is @output, 19, "No multiple substitution problems";
