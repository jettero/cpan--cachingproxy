#!/usr/bin/perl
# vi:tw=0:
# $Id$

use strict;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use Cache::File;
use Data::Dumper;
use LWP::UserAgent;

# wget -O MIRRORED.BY http://www.cpan.org/MIRRORED.BY

my @mirrors = (
  # "ftp://cpan-sj.viaverio.com/pub/CPAN/",
  # "http://ftp.wayne.edu/cpan/",
    "http://cpan.calvin.edu/pub/CPAN",
);
my $mirror = $mirrors[ rand @mirrors ];

my $cgi   = new CGI;
my $pinfo = $ENV{PATH_INFO};
   $pinfo =~ s/^\///;
my $CK    = "CPM:$pinfo";
my $again = 0;

THE_TOP: # we regen the cache each time just in case things aren't flushed correctly... probably don't need to though
my $cache = Cache::File->new(cache_root=>"/home/voltar/nobody.cache/", default_expires => '2 day' );
if( $cache->exists($CK) and $cache->exists("$CK.hdr") ) { our $VAR1;
    my $res = eval $cache->get( "$CK.hdr" ); die "problem finding cache entry\n" if $@;

    my $status = $res->status_line;

    warn "[DEBUG] status: $status";
    print $cgi->header(-status=>$status, -type=>$res->header( 'content-type' ));

    my $fh  = $cache->handle( $CK, "<" ) or die "problem finding cache entry\n";

    if( $res->is_success ) {
        my $buf;
        while( read $fh, $buf, 4096 ) {
            print $buf;
        }

    } else {
        print $status;
    }

    close $fh;

    unless( $res->is_success ) {
        warn "[DEBUG] removing $CK";
        $cache->remove($CK);
    }

    exit 0;

} elsif( not $again ) {
    $again = 1;

    my $ua = new LWP::UserAgent;
       $ua->agent("CPM/0.1 (voltarian cpan proxy-cache)");

    $cache->set($CK, 1); # doesn't seem like we should ahve to do this, but apparently we do

    warn "[DEBUG] getting $mirror/$pinfo";

    my $fh = $cache->handle( $CK, ">" );
    my $request  = HTTP::Request->new(GET => "$mirror/$pinfo");
    my $response = $ua->request($request, sub { my $chunk = shift; print $fh $chunk });
    close $fh;

    warn "[DEBUG] setting $CK";
    $cache->set("$CK.hdr", Dumper($response));

    goto THE_TOP;
}

die "problem fetching $pinfo. :(\n";
