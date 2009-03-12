use Test::More tests=>2;

my @output = `bin/simple_scan <examples/ss_nodouble.in`;
ok @output, "got output"; 
is @output, 6, "No loop over non-substituted line";
