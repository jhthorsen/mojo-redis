package Mojo::Redis::Cache;
use Mojo::Base -base;

use Scalar::Util 'blessed';
use Storable ();

has connection  => sub { shift->redis->_dequeue };
has deserialize => sub { \&Storable::thaw };
has default_expire => 600;
has namespace      => 'cache:mojo:redis';
has redis          => sub { Carp::confess('redis is required in constructor') };
has serialize      => sub { \&Storable::freeze };

sub compute_p {
  my $compute = pop;
  my $self    = shift;
  my $key     = join ':', $self->namespace, shift;
  my $conn    = $self->connection;
  my @args    = @_;

  # Data is stored as a serialized array-ref in Redis, so no need to check for defined
  return $conn->write_p(GET => $key)->then(sub {
    return $_[0] ? $self->deserialize->($_[0])->[0] : $self->_compute_p($conn, $key, @args, $compute);
  });
}

sub _compute_p {
  my $compute = pop;
  my ($self, $conn, $key) = (shift, shift, shift);
  my $expire = 1000 * (@_ ? shift : $self->default_expire);

  my $set = sub {
    my $res = shift;
    return $conn->write_p(SET => $key => $self->serialize->([$res]))->then(sub {
      return $conn->write_p(PEXPIRE => $key => $expire);
    })->then(sub {
      return $res;
    });
  };

  my $res = $compute->();
  return blessed $res ? $res->then(sub { $set->(@_) }) : $set->($res);
}

1;

=encoding utf8

=head1 NAME

Mojo::Redis::Cache - Simple cache interface using Redis

=head1 SYNOPSIS

  use Mojo::Redis;

  my $redis = Mojo::Redis->new;
  my $cache = $redis->cache;

  $cache->compute_p("some:key", 60.7, sub {
    my $p = Mojo::Promise->new;
    Mojo::IOLoop->timer(0.1 => sub { $p->resolve("some data") });
    return $p;
  });

  $cache->compute_p("some:key", sub {
    return {some => "data"};
  });

=head1 DESCRIPTION

L<Mojo::Redis::Cache> provides a simple interface for caching data in the Redis
database.

=head1 ATTRIBUTES

=head2 connection

  $conn = $self->connection;
  $self = $self->connection(Mojo::Redis::Connection->new);

Holds a L<Mojo::Redis::Connection> object.

=head2 default_expire

  $num  = $self->default_expire;
  $self = $self->default_expire(600);

Holds the default expire time for cached data.

=head2 deserialize

  $cb   = $self->deserialize;
  $self = $self->deserialize(\&Mojo::JSON::decode_json);

Holds a callback used to deserialize data from Redis.

=head2 namespace

  $str  = $self->namespace;
  $self = $self->namespace("cache:mojo:redis");

Prefix for the cache key.

=head2 redis

  $conn = $self->connection;
  $self = $self->connection(Mojo::Redis::Connection->new);

Holds a L<Mojo::Redis> object used to create the connections to talk with Redis.

=head2 serialize

  $cb   = $self->serialize;
  $self = $self->serialize(\&Mojo::JSON::encode_json);

Holds a callback used to serialize before storing the data in Redis.

=head1 METHODS

=head2 compute_p

  $promise = $self->compute_p($key => $expire => sub { return "data" });
  $promise = $self->compute_p($key => $expire => sub { return Mojo::Promise->new });

This method will get/set data in the Redis cache. C<$key> will be prefixed by
L</namespace> resulting in "namespace:some-key". C<$expire> is the number of
seconds before the cache should be expire, and the callback is used to
calculate a new value for the cache.

=head1 SEE ALSO

L<Mojo::Redis>

=cut
