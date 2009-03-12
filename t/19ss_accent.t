use Test::More tests=>1;
@output = `echo "http://fake.video.fr/q=clips+pour+madonna /Recherche de vidéos <b>pour/ Y French video matches"| perl -Iblib/lib bin/simple_scan -gen`;
@expected = (map {"$_\n"} (split /\n/,<<EOS));
use Test::More tests=>2;
use Test::WWW::Simple;
page_like "http://fake.video.fr/q=clips+pour+madonna",
          qr/Recherche de vid(.)os <b>pour/,
          "French video matches [http://fake.video.fr/q=clips+pour+madonna] [/Recherche de vid(.)os <b>pour/ should match]";
is \$1, chr(233), "Accent char 1 as expected";
EOS
is_deeply [@output], [@expected], "got expected output";
