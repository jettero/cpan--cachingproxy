# vi:set syntax=perl:

use 5.008;
use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'         => 'CPAN::CachingProxy',
    'VERSION_FROM' => 'CachingProxy.pm',

    'PREREQ_PM'     => { 
        'Cache::File'  => 0,
        'Data::Dumper' => 0,
        LWP            => 0,
        version        => 0,
    },

    ($ExtUtils::MakeMaker::VERSION ge '6.48'? 
        (MIN_PERL_VERSION => 5.008,
            META_MERGE => {
                keywords => ['CPAN','cache'],
                resources=> {
                    repository => 'http://github.com/jettero/cpan--cachingproxy/tree',
                },
            },

        LICENSE	=> 'lgpl2',
    ) : ()),
);
