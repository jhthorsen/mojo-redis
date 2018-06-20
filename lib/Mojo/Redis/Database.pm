package Mojo::Redis::Database;
use Mojo::Base 'Mojo::EventEmitter';

our @BASIC_OPERATIONS = (
  'append',           'echo',        'decr',             'decrby',   'del',      'exists',
  'expire',           'expireat',    'get',              'getbit',   'getrange', 'getset',
  'hdel',             'hexists',     'hget',             'hgetall',  'hincrby',  'hkeys',
  'hlen',             'hmget',       'hmset',            'hset',     'hsetnx',   'hvals',
  'incr',             'incrby',      'keys',             'lindex',   'linsert',  'llen',
  'lpop',             'lpush',       'lpushx',           'lrange',   'lrem',     'lset',
  'ltrim',            'mget',        'move',             'mset',     'msetnx',   'persist',
  'ping',             'publish',     'randomkey',        'rename',   'renamenx', 'rpop',
  'rpoplpush',        'rpush',       'rpushx',           'sadd',     'scard',    'sdiff',
  'sdiffstore',       'set',         'setbit',           'setex',    'setnx',    'setrange',
  'sinter',           'sinterstore', 'sismember',        'smembers', 'smove',    'sort',
  'spop',             'srandmember', 'srem',             'strlen',   'sunion',   'sunionstore',
  'ttl',              'type',        'zadd',             'zcard',    'zcount',   'zincrby',
  'zinterstore',      'zrange',      'zrangebyscore',    'zrank',    'zrem',     'zremrangebyrank',
  'zremrangebyscore', 'zrevrange',   'zrevrangebyscore', 'zrevrank', 'zscore',   'zunionstore'
);

has connection => sub { Carp::confess('connection is not set') };
has redis      => sub { Carp::confess('redis is not set') };

for my $method (@BASIC_OPERATIONS) {
  my $op = uc $method;
  Mojo::Util::monkey_patch(__PACKAGE__,
    $method => sub {
      my $cb   = ref $_[-1] eq 'CODE' ? pop : undef;
      my $self = shift;
      my $conn = $cb ? $self->connection : $self->redis->_blocking_connection;
      my @res;

      $conn->write($op, @_, $cb ? ($cb) : sub { shift->loop->stop; @res = @_ });

      # Non-blocking
      return $self if $cb;

      # Blocking
      $conn->loop->start;
      die $res[0] if $res[0];
      return $res[1];
    }
  );
}

sub DESTROY {
  my $self = shift;
  return unless (my $redis = $self->redis) && (my $conn = $self->connection);
  $redis->_enqueue($conn);
}

1;
