use Test::More tests=>26;

BEGIN {
  use_ok(qw(App::SimpleScan));
  use_ok(qw( App::SimpleScan::TestSpec));
}
my $app = new App::SimpleScan;
App::SimpleScan::TestSpec->app($app);

while (<DATA>) {
  my $spec = 
  new App::SimpleScan::TestSpec($_);

  my $regex = <DATA>;
  chomp $regex;
  is $spec->regex, $regex, "right regex data";
   
  my $delim = <DATA>;
  chomp $delim;
  is $spec->delim, $delim, "right delim data";
   
  my $uri = <DATA>;
  chomp $uri;
  is $spec->uri, $uri, "right uri data";
   
  my $kind = <DATA>;
  chomp $kind;
  is $spec->kind, $kind, "right kind data";
   
  my $comment = <DATA>;
  chomp $comment;
  is $spec->comment, $comment, "right comment data";
   
  my $metaquote = <DATA>;
  chomp $metaquote;
  $metaquote = undef if $metaquote eq "undef";
  is $spec->metaquote, $metaquote, "right metaquote data";
}   
__DATA__
http://search.yahoo.com/ m|yahoo</b>| TY /No comment/
yahoo</b>
|
http://search.yahoo.com/
TY
/No comment/
undef
http://search.yahoo.com/ /yahoo</b>/ SN /No comment/
yahoo</b>
/
http://search.yahoo.com/
SN
/No comment/
1
http://search.yahoo.com/ <b**Yahoo!**</b> SN (*No comment*)
<b**Yahoo!**</b>
/
http://search.yahoo.com/
SN
(*No comment*)
1
http://uk.search.yahoo.com/search?p=image+flower /<b>Image</b> Search Results for <b>flower</b>/ Y UK Image SC
<b>Image</b> Search Results for <b>flower</b>
/
http://uk.search.yahoo.com/search?p=image+flower
Y
UK Image SC
1
