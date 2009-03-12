use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'App::SimpleScan',
    AUTHOR              => 'Joe McMahon <mcmahon@yahoo-inc.com >',
    VERSION_FROM        => 'lib/App/SimpleScan.pm',
    ABSTRACT_FROM       => 'lib/App/SimpleScan.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More'           => 0,
        'Test::WWW::Simple'    => 0.18,
        'Test::Differences'    => 0,
        'Scalar::Util'         => 0,
        'Getopt::Long'         => 0,
        'Regexp::Common'       => 0,
        'WWW::Mechanize'       => '1.16',
        'WWW::Mechanize::Pluggable' => '0.09',
        'Text::Balanced'       => '1.95',

    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'App-SimpleScan-*' },
    EXE_FILES           => [ 'bin/simple_scan' ],
    
);
