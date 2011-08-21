#!/usr/bin/perl

package CPAN::CachingProxy;

use strict;
use Carp;
use Cache::File;
use Data::Dumper;
use LWP::UserAgent;

our $VERSION = "1.5000";

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
        $this->{cache_root}      = "/tmp/ccp/" unless exists $this->{cache_root};
        $this->{default_expire} = "2 day"      unless exists $this->{default_expire};
        $this->{index_expire}   = "3 hour"     unless exists $this->{index_expire};
        $this->{error_expire}   = "15 minute"  unless exists $this->{error_expire};

        $this->{index_regexp}   = qr/(?:03modlist\.data|02packages\.details\.txt|01mailrc\.txt)/ unless exists $this->{index_regexp};
        $this->{cache_object}   = Cache::File->new(cache_root=>$this->{cache_root}, default_expires => $this->{default_expire} );
    }

    $this->{key_space}        = "CK" unless $this->{key_space};

    unless( $this->{ua} ) {
        my $ua = $this->{ua} = new LWP::UserAgent;
           $ua->agent($this->{agent} ? $this->{agent} : "CCP/$VERSION (Paul's CPAN caching proxy / perlmonks-id=16186)");
           if( exists $this->{activity_timeout} ) {
               if( defined (my $at = $this->{activity_timeout}) ) {
                   $ua->timeout($at);
               }

           } else {
               $ua->timeout(12);
           }
    }

    $this->{ua}->timeout( $this->{activity_timeout} ) if defined $this->{activity_timeout};

    croak "there are no default mirrors, they must be set" unless $this->{mirrors};

    return $this;
}
# }}}
# run {{{
sub run {
    my $this   = shift;
    my $cgi    = $this->{cgi};
    my $mirror = $this->{mirrors}[ rand @{$this->{mirrors}} ];
    my $pinfo  = $cgi->path_info || return print $cgi->redirect( $cgi->url . "/" );
       $pinfo =~ s/^\///;
       $mirror=~ s/\/$//;

    my $CK    = "$this->{key_space}:$pinfo";

    my $cache = $this->{cache_object};
    if( $cache->exists($CK) and $cache->exists("$CK.hdr") ) { our $VAR1;
        my $res = eval $cache->get( "$CK.hdr" ); die "problem finding cache entry\n" if $@;
        $this->my_copy_hdr($res, "cache hit");

        my $fh = $cache->handle( $CK, "<" ) or die "problem finding cache entry\n";
        my $buf;
        while( read $fh, $buf, 4096 ) {
            print $buf;
        }
        close $fh;

        unless( $res->is_success ) {
            warn "[DEBUG] removing $CK" if $this->{debug};
            $cache->remove($CK);
        }

        return;

    } else {
        my $expire = $this->{default_expire};
           $expire = $this->{index_expire} if $pinfo =~ $this->{index_regexp};

        $cache->set($CK, 1, $expire ); # doesn't seem like we should have to do this, but apparently we do

        my $URL = "$mirror/$pinfo";
         # $URL =~ s/\/{2,}/\//g;

        warn "[DEBUG] getting $URL" if $this->{debug};

        my $fh       = $cache->handle( $CK, ">", $expire );
        my $request  = HTTP::Request->new(GET => $URL);

        my $announced_header;
        my $response = $this->{ua}->request($request, sub {
            my $chunk = shift;

            unless( $announced_header ) {
                $announced_header = 1;
                $this->my_copy_hdr(shift, "cache miss");
            }

            print $fh $chunk;
            print     $chunk;
        });
        close $fh;

        warn "[DEBUG] setting $CK" if $this->{debug};
        $cache->set("$CK.hdr", Dumper($response), $expire);

        # if there was an error (which we don't know until ex post facto), go back and fix the expiry
        if( defined $this->{error_expire} and not $response->is_success ) {
            $cache->set_expiry( $CK       => $this->{error_expire} );
            $cache->set_expiry( "$CK.hdr" => $this->{error_expire} );
        }
    }
}
# }}}

# {{{ sub my_copy_hdr
sub my_copy_hdr {
    my ($this, $res, $hit) = @_;
    my $cgi = $this->{cgi};

    my $status = $res->status_line;
    warn "[DEBUG] cache status: $hit; status: $status" if $this->{debug};
    print $cgi->header(-status=>$status, -type=>$res->header( 'content-type' ));
}

# }}}
