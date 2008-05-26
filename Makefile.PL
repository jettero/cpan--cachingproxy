# vi:set syntax=perl:

use 5.008;
use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'         => 'CPAN::CachingProxy',
    'VERSION_FROM' => 'CachingProxy.pm',
    'PREREQ_PM'     => { 
        'Software::License::LGPL_2_1' => 0,
        'Cache::File'                 => 0,
        'Data::Dumper'                => 0,
        LWP     => 0,
        version => 0,
    },

    # clean => { FILES => "m*.txt map.png *.log *.map [0-9][0-9]_*.xml m*.xml 10_groups.* map.dumper.* log" },
);
