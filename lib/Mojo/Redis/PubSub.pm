package Mojo::Redis::PubSub;
use Mojo::Base 'Mojo::EventEmitter';

has connection => sub { shift->redis->_connection };
has redis      => sub { Carp::confess('redis is requried in constructor') };

has _db => sub {
  my $db = shift->redis->db;
  Scalar::Util::weaken($db->{redis});
  return $db;
};

sub listen {
  my ($self, $name, $cb) = @_;
  my $op = $name =~ /\*/ ? 'PSUBSCRIBE' : 'SUBSCRIBE';

  Scalar::Util::weaken($self);
  $self->connection->write_p($op => $name)->then(sub { $self->_setup }) unless @{$self->{chans}{$name} ||= []};
  push @{$self->{chans}{$name}}, $cb;

  return $cb;
}

sub notify {
  shift->_db->connection->write_p(PUBLISH => @_);
}

sub unlisten {
  my ($self, $name, $cb) = @_;
  my $chan = $self->{chans}{$name};
  my $op = $name =~ /\*/ ? 'PUNSUBSCRIBE' : 'UNSUBSCRIBE';

  @$chan = $cb ? grep { $cb ne $_ } @$chan : ();
  $self->connection->write_p($op => $name) and delete $self->{chans}{$name} unless @$chan;

  return $self;
}

sub _setup {
  my $self = shift;
  return if $self->{cb};

  Scalar::Util::weaken($self);
  $self->{cb} = $self->connection->on(
    message => sub {
      my ($conn, $type, $name, $payload) = @_;
      for my $cb (@{$self->{chans}{$name}}) { $self->$cb($payload) }
    }
  );
}

1;

=encoding utf8

=head1 NAME

Mojo::Redis::PubSub - Publish and subscribe to Redis messages

=head1 SYNOPSIS

  use Mojo::Redis;

  my $redis  = Mojo::Redis->new;
  my $pubsub = $redis->pubsub;

  $pubsub->listen("user:superwoman:messages" => sub {
    my ($pubsub, $message) = @_;
    say "superwoman got a message: $message";
  });

  $pubsub->notify("user:batboy:messages", "How are you doing?");

=head1 DESCRIPTION

L<Mojo::Redis::PubSub> is an implementation of the Redis Publish/Subscribe
messaging paradigm. This class has the same API as L<Mojo::Pg::PubSub>, so
you can easily switch between the backends.

This object holds one connection for receiving messages, and one connection
for sending messages. They are created lazily the first time L</listen> or
L</notify> is called. These connections does not affect the connection pool
for L<Mojo::Redis>.

See L<pubsub|https://redis.io/topics/pubsub> for more details.

=head1 ATTRIBUTES

=head2 connection

  $conn = $self->connection;
  $self = $self->connection(Mojo::Redis::Connection->new);

Holds a L<Mojo::Redis::Connection> object.

=head2 redis

  $conn = $self->connection;
  $self = $self->connection(Mojo::Redis::Connection->new);

Holds a L<Mojo::Redis> object used to create the connections to talk with Redis.

=head1 METHODS

=head2 listen

  $cb = $self->listen($channel => sub { my ($self, $message) = @_ });

Subscribe to a channel, there is no limit on how many subscribers a channel
can have. The returning code ref can be passed on to L</unlisten>.

=head2 notify

  $self->notify($channel => $message);

Send a plain string message to a channel.

=head2 unlisten

  $self = $self->unlisten($channel);
  $self = $self->unlisten($channel, $cb);

Unsubscribe from a channel.

=head1 SEE ALSO

L<Mojo::Redis>.

=cut
