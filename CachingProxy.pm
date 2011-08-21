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

    $this->{key_space} = "CK" unless $this->{key_space};

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

    my $CK = "$this->{key_space}:$pinfo";

    my $URL = "$mirror/$pinfo";
     # $URL =~ s/\/{2,}/\//g;

    my $cache = $this->{cache_object};
    if( $cache->exists($CK) and $cache->exists("$CK.hdr") ) { our $VAR1;
        my $res = eval $cache->get( "$CK.hdr" ); die "problem finding cache entry\n" if $@;

        unless( $this->{ignore_last_modified} ) {
            if( my $lm = $res->header('last_modified') ) {
                my $_lm = eval { $this->{ua}->head($URL)->header('last_modified') };

                # $lm = "hehe, random failure time" if (int rand(7)) == 0;

                if( $_lm and $lm ne $_lm ) {
                    warn "[DEBUG] last_modified differs ($lm vs $_lm), forcing cache miss\n" if $this->{debug};
                    goto FORCE_CACHE_MISS;
                }
            }
        }

        $this->my_copy_hdr($res, "cache hit");

        my $fh = $cache->handle( $CK, "<" ) or die "problem finding cache entry\n";
        my $buf;
        while( read $fh, $buf, 4096 ) {
            print $buf;
        }
        close $fh;

    } else {
        FORCE_CACHE_MISS:
        my $expire = $this->{default_expire};
           $expire = $this->{index_expire} if $pinfo =~ $this->{index_regexp};

        $cache->set($CK, 1, $expire ); # doesn't seem like we should have to do this, but apparently we do

        warn "[DEBUG] getting $URL\n" if $this->{debug};

        my $fh       = $cache->handle( $CK, ">", $expire );
        my $request  = HTTP::Request->new(GET => $URL);

        my $announced_header;
        my $response = $this->{ua}->request($request, sub {
            my $chunk = shift;

            unless( $announced_header ) {
                my $res = shift;
                $announced_header = 1;
                $this->my_copy_hdr($res, "cache miss");
            }

            print $fh $chunk;
            print     $chunk;
        });
        close $fh;

        unless( $response->is_success ) {
            my $my_fail = "FAIL: " . $response->status_line . "\n";
            $cache->set($CK => $my_fail, $expire);
            $response->header(content_length=>length $my_fail); # fix content length so we don't lie to clients

            $this->my_copy_hdr($response, "cache miss [fail]");
            print $my_fail;
        }

        warn "[DEBUG] setting $CK\n" if $this->{debug};
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
    warn "[DEBUG] cache status: $hit; status: $status\n" if $this->{debug};

    my @more_headers = (qw(accept_ranges bytes));

    for(qw(content_length), $this->{ignore_last_modified} ? ():(qw(last_modified))) {
        my $v = $res->header($_);
        push @more_headers, ($_=>$v) if $v;
    }

    print $cgi->header(-status=>$status, -charset=>"", -type=>$res->header( 'content-type' ), @more_headers);
}

# }}}
