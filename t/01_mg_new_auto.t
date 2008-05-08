
use strict;
use Test;

plan tests => 1;

eval 'use CPAN::CachingProxy;';

ok( not $@ );
