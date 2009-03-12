use Test::More tests=>1;
use Test::Differences;
@output = `echo "http://fake.video.fr/q=clips+pour+madonna /(Recherche) de vidéos <b>pour/ Y French video matches"| perl -Iblib/lib bin/simple_scan -gen`;
@expected = (map {"$_\n"} (split /\n/,<<EOS));
use Test::More tests=>2;
use Test::WWW::Simple;
use strict;

my \@accent;
mech->agent_alias('Windows IE 6');
page_like "http://fake.video.fr/q=clips+pour+madonna",
          qr/(Recherche) de vid(.|..)os <b>pour/,
          qq(French video matches [http://fake.video.fr/q=clips+pour+madonna] [/(Recherche) de vid(.|..)os <b>pour/ should match]);
\@accent = (mech->content =~ /(Recherche) de vid(.|..)os <b>pour/);
is \$accent[0], "é", "Accent char 0 as expected";
EOS
push @expected,"\n";
eq_or_diff [@output], [@expected], "got expected output";
