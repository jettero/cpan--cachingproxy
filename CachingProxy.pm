#!/usr/bin/perl
# vi:tw=0:
# $Id$

use strict;
use Carp;
use Cache::File;
use Data::Dumper;
use LWP::UserAgent;

our $VERSION = "1.0.0";

# wget -O MIRRORED.BY http://www.cpan.org/MIRRORED.BY

# new {{{
sub new {
    my $class = shift;
    my $this  = bless {@_}, $class;

    unless( $this->{cgi} ) {
        require CGI or die $@;
        $this->{cgi} = new CGI;
    }

    unless( $this->{cf} ) {
        $this->{cache_root}      = "/tmp/ccp/" unless $this->{cache_root};
        $this->{default_expires} = "2 day"     unless $this->{default_expires};

        my $cache = Cache::File->new(cache_root=>$this->{cache_root}, default_expires => $this->{default_expires} );
    }

    $this->{key_space} = "CK" unless $this->{key_space};

    unless( $this->{ua} ) {
        my $ua = $this->{ua} = new LWP::UserAgent;
           $ua->agent($this->{agent} ? $this->{agent} : "PPC/0.1 (paul's proxy cache perlmonks-id=16186)");
    }

    croak "there are no default mirrors, they must be set" unless $this->{mirrors};

    return $this;
}
# }}}
# run {{{
sub run {
    my $this   = shift;
    my $mirror = $this->{mirrors}[ rand @{$this->{mirrors}} ];
    my $pinfo  = $ENV{PATH_INFO};
       $pinfo =~ s/^\///;

    my $CK    = "$this->{key_space}:$pinfo";
    my $cgi   = $this->{cgi};
    my $again = 0;

    THE_TOP:
    my $cache = $this->{cf};
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

        return;

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
}
# }}}
