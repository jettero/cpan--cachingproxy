
use strict;
use Test;

plan tests => 2;

eval 'use CPAN::CachingProxy;';

ok( not $@ );

eval 'my $n = CPAN::CachingProxy->new(mirrors=>["blah"])';

ok( not $@ );
