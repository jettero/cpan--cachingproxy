#!/usr/bin/perl

package CPAN::CachingProxy;

use strict;
use Carp;
use Cache::File;
use Data::Dumper;
use LWP::UserAgent;

our $VERSION = 1.2;

# wget -O MIRRORED.BY http://www.cpan.org/MIRRORED.BY

# new {{{
sub new {
    my $class = shift;
    my $this  = bless {@_}, $class;

    unless( $this->{cgi} ) {
        require CGI or die $@;
        $this->{cgi} = new CGI;
    }

    unless( $this->{cache_object} ) {
        $this->{cache_root}      = "/tmp/ccp/" unless $this->{cache_root};
        $this->{default_expires} = "2 day"     unless $this->{default_expires};
        $this->{index_expires}   = "3 hour"    unless $this->{index_expires};

        $this->{cache_object} = Cache::File->new(cache_root=>$this->{cache_root}, default_expires => $this->{default_expires} );
    }

    $this->{key_space} = "CK" unless $this->{key_space};

    unless( $this->{ua} ) {
        my $ua = $this->{ua} = new LWP::UserAgent;
           $ua->agent($this->{agent} ? $this->{agent} : "CCP/$VERSION (Paul's CPAN caching proxy / perlmonks-id=16186)");
    }

    croak "there are no default mirrors, they must be set" unless $this->{mirrors};

    return $this;
}
# }}}
# run {{{
sub run {
    my $this   = shift;
    my $cgi    = $this->{cgi};
    my $mirror = $this->{mirrors}[ rand @{$this->{mirrors}} ];
    my $pinfo  = $cgi->path_info;
       $pinfo =~ s/^\///;
       $mirror=~ s/\/$//;

    my $CK    = "$this->{key_space}:$pinfo";
    my $again = 0;

    THE_TOP:
    my $cache = $this->{cache_object};
    if( $cache->exists($CK) and $cache->exists("$CK.hdr") ) { our $VAR1;
        my $res = eval $cache->get( "$CK.hdr" ); die "problem finding cache entry\n" if $@;

        my $status = $res->status_line;

        warn "[DEBUG] status: $status" if $this->{debug};
        print $cgi->header(-status=>$status, -type=>$res->header( 'content-type' ));

        if( $res->is_success ) {
            my $fh = $cache->handle( $CK, "<" ) or die "problem finding cache entry\n";
            my $buf;
            while( read $fh, $buf, 4096 ) {
                print $buf;
            }
            close $fh;

        } else {
            print $status;
        }

        unless( $res->is_success ) {
            warn "[DEBUG] removing $CK" if $this->{debug};
            $cache->remove($CK);
        }

        return;

    } elsif( not $again ) {
        $again = 1;

        my $expire = $this->{default_expire};
           $expire = $this->{index_expire}
               if $pinfo =~ m/(?:03modlist\.data|02packages\.details\.txt|01mailrc\.txt)/;

        $cache->set($CK, 1, $expire ); # doesn't seem like we should have to do this, but apparently we do

        my $URL = "$mirror/$pinfo";
         # $URL =~ s/\/{2,}/\//g;

        warn "[DEBUG] getting $URL" if $this->{debug};

        my $fh = $cache->handle( $CK, ">", $expire );
        my $request  = HTTP::Request->new(GET => $URL);
        my $response = $this->{ua}->request($request, sub { my $chunk = shift; print $fh $chunk });
        close $fh;

        warn "[DEBUG] setting $CK" if $this->{debug};
        $cache->set("$CK.hdr", Dumper($response), $expire);

        goto THE_TOP;
    }

    die "problem fetching $pinfo. :(\n";
}
# }}}
