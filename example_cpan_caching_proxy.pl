#!/usr/bin/perl
# vi:tw=0:
# $Id$

use strict;
use CPAN::CachingProxy;
use CGI;
use CGI::Carp qw(fatalsToBrowser);

die "please use 'wget -O MIRRORED.BY http://www.cpan.org/MIRRORED.BY | grep dst_http' to select a proxy";

my $cache = CPAN::CachingProxy->new(mirrors=>['http://www.perl.com/CPAN/']);
   $cache->run;
