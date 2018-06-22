package Mojo::Redis;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::URL;
use Mojo::Redis::Connection;
use Mojo::Redis::Database;
use Mojo::Redis::PubSub;

our $VERSION = '3.00';

has max_connections => 5;

has protocol_class => do {
  my $class = $ENV{MOJO_REDIS_PROTOCOL};
  $class ||= eval q(require Protocol::Redis::XS; 'Protocol::Redis::XS');
  $class ||= 'Protocol::Redis';
  eval "require $class; 1" or die $@;
  $class;
};

has pubsub => sub {
  my $pubsub = Mojo::Redis::PubSub->new(redis => $_[0]);
  Scalar::Util::weaken($pubsub->{redis});
  return $pubsub;
};

has url => sub { Mojo::URL->new('redis://localhost:6379') };

# TODO: Should this attribute be public?
has _blocking_connection => sub { shift->_connection(ioloop => Mojo::IOLoop->new) };

sub db { Mojo::Redis::Database->new(connection => $_[0]->_dequeue, redis => $_[0]); }
sub new { @_ == 2 ? $_[0]->SUPER::new->url(Mojo::URL->new($_[1])) : $_[0]->SUPER::new }

sub _connection {
  my ($self, %args) = @_;

  $args{ioloop} ||= Mojo::IOLoop->singleton;
  my $conn = Mojo::Redis::Connection->new(protocol => $self->protocol_class->new(api => 1), url => $self->url, %args);

  Scalar::Util::weaken($self);
  $conn->on(connect => sub { $self->emit(connection => $_[0]) });
  $conn;
}

sub _dequeue {
  my $self = shift;
  delete @$self{qw(pid queue)} unless ($self->{pid} //= $$) eq $$;    # Fork-safety

  # Exsting connection
  while (my $conn = shift @{$self->{queue} || []}) { return $conn if $conn->is_connected }

  # New connection
  return $self->_connection;
}

sub _enqueue {
  my ($self, $conn) = @_;
  my $queue = $self->{queue} ||= [];
  push @$queue, $conn if $conn->is_connected;
  shift @$queue while @$queue > $self->max_connections;
}

1;

=encoding utf8

=head1 NAME

Mojo::Redis - Redis driver based on Mojo::IOLoop

=head1 SYNOPSIS

  use Mojo::Redis;

  my $redis = Mojo::Redis->new;

  $redis->db->get_p("mykey")->then(sub {
    print "mykey=$_[0]\n";
  })->catch(sub {
    warn "Could not fetch mykey: $_[0]";
  })->wait;

=head1 DESCRIPTION

L<Mojo::Redis> is a Redis driver that use the L<Mojo::IOLoop>, which makes it
integrate easily with the L<Mojolicious> framework.

It tries to mimic the same interface as L<Mojo::Pg>, L<Mojo::mysql> and
L<Mojo::SQLite>, but the methods for talking to the database vary.

This module is in no way compatible with the 1.xx version of L<Mojo::Redis>
and this version also tries to fix a lot of the confusing methods in
L<Mojo::Redis2> related to pubsub.

=head1 ATTRIBUTES

=head2 max_connections

  $int = $self->max_connections;
  $self = $self->max_connections(5);

Maximum number of idle database handles to cache for future use, defaults to
5. (Default is subject to change)

=head2 protocol_class

  $str = $self->protocol_class;
  $self = $self->protocol_class("Protocol::Redis::XS");

Default to L<Protocol::Redis::XS> if the optional module is available, or
falls back to L<Protocol::Redis>.

=head2 pubsub

  $pubsub = $self->pubsub;

Lazy builds an instance of L<Mojo::Redis::PubSub> for this object, instead of
returning a new instance like L</db> does.

=head2 url

  $url = $self->url;
  $self = $self->url(Mojo::URL->new("redis://localhost/3"));

Holds an instance of L<Mojo::URL> that describes how to connect to the Redis server.

=head1 METHODS

=head2 db

  $db = $self->db;

Returns an instance of L<Mojo::Redis::Database>.

=head2 new

  $self = Mojo::Redis->new("redis://localhost:6379/1");
  $self = Mojo::Redis->new(\%attrs);
  $self = Mojo::Redis->new(%attrs);

Object constructor. Can coerce a string into a L<Mojo::URL> and set L</url>
if present.

=head1 AUTHOR

Jan Henning Thorsen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018, Jan Henning Thorsen.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojo::Redis2>.

=cut
