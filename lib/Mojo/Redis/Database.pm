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

has connection => sub { Carp::confess('connection is required in constructor') };
has redis      => sub { Carp::confess('redis is required in constructor') };

for my $method (@BASIC_OPERATIONS) {
  my $op = uc $method;

  Mojo::Util::monkey_patch(__PACKAGE__, "${method}_p" => sub { shift->connection->write_p($op => @_) });

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

=encoding utf8

=head1 NAME

Mojo::Redis::Database - Execute basic redis commands

=head1 SYNOPSIS

  use Mojo::Redis;

  my $redis = Mojo::Redis->new;
  my $db    = $redis->db;

  # Blocking
  say "foo=" .$db->get("foo");

  # Non-blocking
  $db->get(foo => sub { my ($db, $res) = @_; say "foo=$res" });

  # Promises
  $db->get_p("foo")->then(sub { my ($res) = @_; say "foo=$res" });

=head1 DESCRIPTION

L<Mojo::Redis::Database> has methods for sending and receiving structured
data to the Redis server.

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

=head2 append

  @res     = $self->append($key, $value);
  $self    = $self->append($key, $value, sub { my ($self, @res) = @_ });
  $promise = $self->append_p($key, $value);

Append a value to a key.

See L<https://redis.io/commands/append> for more information.

=head2 decr

  @res     = $self->decr($key);
  $self    = $self->decr($key, sub { my ($self, @res) = @_ });
  $promise = $self->decr_p($key);

Decrement the integer value of a key by one.

See L<https://redis.io/commands/decr> for more information.

=head2 decrby

  @res     = $self->decrby($key, $decrement);
  $self    = $self->decrby($key, $decrement, sub { my ($self, @res) = @_ });
  $promise = $self->decrby_p($key, $decrement);

Decrement the integer value of a key by the given number.

See L<https://redis.io/commands/decrby> for more information.

=head2 del

  @res     = $self->del($key [key ...]);
  $self    = $self->del($key [key ...], sub { my ($self, @res) = @_ });
  $promise = $self->del_p($key [key ...]);

Delete a key.

See L<https://redis.io/commands/del> for more information.

=head2 echo

  @res     = $self->echo($message);
  $self    = $self->echo($message, sub { my ($self, @res) = @_ });
  $promise = $self->echo_p($message);

Echo the given string.

See L<https://redis.io/commands/echo> for more information.

=head2 exists

  @res     = $self->exists($key [key ...]);
  $self    = $self->exists($key [key ...], sub { my ($self, @res) = @_ });
  $promise = $self->exists_p($key [key ...]);

Determine if a key exists.

See L<https://redis.io/commands/exists> for more information.

=head2 expire

  @res     = $self->expire($key, $seconds);
  $self    = $self->expire($key, $seconds, sub { my ($self, @res) = @_ });
  $promise = $self->expire_p($key, $seconds);

Set a key's time to live in seconds.

See L<https://redis.io/commands/expire> for more information.

=head2 expireat

  @res     = $self->expireat($key, $timestamp);
  $self    = $self->expireat($key, $timestamp, sub { my ($self, @res) = @_ });
  $promise = $self->expireat_p($key, $timestamp);

Set the expiration for a key as a UNIX timestamp.

See L<https://redis.io/commands/expireat> for more information.

=head2 get

  @res     = $self->get($key);
  $self    = $self->get($key, sub { my ($self, @res) = @_ });
  $promise = $self->get_p($key);

Get the value of a key.

See L<https://redis.io/commands/get> for more information.

=head2 getbit

  @res     = $self->getbit($key, $offset);
  $self    = $self->getbit($key, $offset, sub { my ($self, @res) = @_ });
  $promise = $self->getbit_p($key, $offset);

Returns the bit value at offset in the string value stored at key.

See L<https://redis.io/commands/getbit> for more information.

=head2 getrange

  @res     = $self->getrange($key, $start, $end);
  $self    = $self->getrange($key, $start, $end, sub { my ($self, @res) = @_ });
  $promise = $self->getrange_p($key, $start, $end);

Get a substring of the string stored at a key.

See L<https://redis.io/commands/getrange> for more information.

=head2 getset

  @res     = $self->getset($key, $value);
  $self    = $self->getset($key, $value, sub { my ($self, @res) = @_ });
  $promise = $self->getset_p($key, $value);

Set the string value of a key and return its old value.

See L<https://redis.io/commands/getset> for more information.

=head2 hdel

  @res     = $self->hdel($key, $field [field ...]);
  $self    = $self->hdel($key, $field [field ...], sub { my ($self, @res) = @_ });
  $promise = $self->hdel_p($key, $field [field ...]);

Delete one or more hash fields.

See L<https://redis.io/commands/hdel> for more information.

=head2 hexists

  @res     = $self->hexists($key, $field);
  $self    = $self->hexists($key, $field, sub { my ($self, @res) = @_ });
  $promise = $self->hexists_p($key, $field);

Determine if a hash field exists.

See L<https://redis.io/commands/hexists> for more information.

=head2 hget

  @res     = $self->hget($key, $field);
  $self    = $self->hget($key, $field, sub { my ($self, @res) = @_ });
  $promise = $self->hget_p($key, $field);

Get the value of a hash field.

See L<https://redis.io/commands/hget> for more information.

=head2 hgetall

  @res     = $self->hgetall($key);
  $self    = $self->hgetall($key, sub { my ($self, @res) = @_ });
  $promise = $self->hgetall_p($key);

Get all the fields and values in a hash.

See L<https://redis.io/commands/hgetall> for more information.

=head2 hincrby

  @res     = $self->hincrby($key, $field, $increment);
  $self    = $self->hincrby($key, $field, $increment, sub { my ($self, @res) = @_ });
  $promise = $self->hincrby_p($key, $field, $increment);

Increment the integer value of a hash field by the given number.

See L<https://redis.io/commands/hincrby> for more information.

=head2 hkeys

  @res     = $self->hkeys($key);
  $self    = $self->hkeys($key, sub { my ($self, @res) = @_ });
  $promise = $self->hkeys_p($key);

Get all the fields in a hash.

See L<https://redis.io/commands/hkeys> for more information.

=head2 hlen

  @res     = $self->hlen($key);
  $self    = $self->hlen($key, sub { my ($self, @res) = @_ });
  $promise = $self->hlen_p($key);

Get the number of fields in a hash.

See L<https://redis.io/commands/hlen> for more information.

=head2 hmget

  @res     = $self->hmget($key, $field [field ...]);
  $self    = $self->hmget($key, $field [field ...], sub { my ($self, @res) = @_ });
  $promise = $self->hmget_p($key, $field [field ...]);

Get the values of all the given hash fields.

See L<https://redis.io/commands/hmget> for more information.

=head2 hmset

  @res     = $self->hmset($key, $field value [field value ...]);
  $self    = $self->hmset($key, $field value [field value ...], sub { my ($self, @res) = @_ });
  $promise = $self->hmset_p($key, $field value [field value ...]);

Set multiple hash fields to multiple values.

See L<https://redis.io/commands/hmset> for more information.

=head2 hset

  @res     = $self->hset($key, $field, $value);
  $self    = $self->hset($key, $field, $value, sub { my ($self, @res) = @_ });
  $promise = $self->hset_p($key, $field, $value);

Set the string value of a hash field.

See L<https://redis.io/commands/hset> for more information.

=head2 hsetnx

  @res     = $self->hsetnx($key, $field, $value);
  $self    = $self->hsetnx($key, $field, $value, sub { my ($self, @res) = @_ });
  $promise = $self->hsetnx_p($key, $field, $value);

Set the value of a hash field, only if the field does not exist.

See L<https://redis.io/commands/hsetnx> for more information.

=head2 hvals

  @res     = $self->hvals($key);
  $self    = $self->hvals($key, sub { my ($self, @res) = @_ });
  $promise = $self->hvals_p($key);

Get all the values in a hash.

See L<https://redis.io/commands/hvals> for more information.

=head2 incr

  @res     = $self->incr($key);
  $self    = $self->incr($key, sub { my ($self, @res) = @_ });
  $promise = $self->incr_p($key);

Increment the integer value of a key by one.

See L<https://redis.io/commands/incr> for more information.

=head2 incrby

  @res     = $self->incrby($key, $increment);
  $self    = $self->incrby($key, $increment, sub { my ($self, @res) = @_ });
  $promise = $self->incrby_p($key, $increment);

Increment the integer value of a key by the given amount.

See L<https://redis.io/commands/incrby> for more information.

=head2 keys

  @res     = $self->keys($pattern);
  $self    = $self->keys($pattern, sub { my ($self, @res) = @_ });
  $promise = $self->keys_p($pattern);

Find all keys matching the given pattern.

See L<https://redis.io/commands/keys> for more information.

=head2 lindex

  @res     = $self->lindex($key, $index);
  $self    = $self->lindex($key, $index, sub { my ($self, @res) = @_ });
  $promise = $self->lindex_p($key, $index);

Get an element from a list by its index.

See L<https://redis.io/commands/lindex> for more information.

=head2 linsert

  @res     = $self->linsert($key, $BEFORE|AFTER, $pivot, $value);
  $self    = $self->linsert($key, $BEFORE|AFTER, $pivot, $value, sub { my ($self, @res) = @_ });
  $promise = $self->linsert_p($key, $BEFORE|AFTER, $pivot, $value);

Insert an element before or after another element in a list.

See L<https://redis.io/commands/linsert> for more information.

=head2 llen

  @res     = $self->llen($key);
  $self    = $self->llen($key, sub { my ($self, @res) = @_ });
  $promise = $self->llen_p($key);

Get the length of a list.

See L<https://redis.io/commands/llen> for more information.

=head2 lpop

  @res     = $self->lpop($key);
  $self    = $self->lpop($key, sub { my ($self, @res) = @_ });
  $promise = $self->lpop_p($key);

Remove and get the first element in a list.

See L<https://redis.io/commands/lpop> for more information.

=head2 lpush

  @res     = $self->lpush($key, $value [value ...]);
  $self    = $self->lpush($key, $value [value ...], sub { my ($self, @res) = @_ });
  $promise = $self->lpush_p($key, $value [value ...]);

Prepend one or multiple values to a list.

See L<https://redis.io/commands/lpush> for more information.

=head2 lpushx

  @res     = $self->lpushx($key, $value);
  $self    = $self->lpushx($key, $value, sub { my ($self, @res) = @_ });
  $promise = $self->lpushx_p($key, $value);

Prepend a value to a list, only if the list exists.

See L<https://redis.io/commands/lpushx> for more information.

=head2 lrange

  @res     = $self->lrange($key, $start, $stop);
  $self    = $self->lrange($key, $start, $stop, sub { my ($self, @res) = @_ });
  $promise = $self->lrange_p($key, $start, $stop);

Get a range of elements from a list.

See L<https://redis.io/commands/lrange> for more information.

=head2 lrem

  @res     = $self->lrem($key, $count, $value);
  $self    = $self->lrem($key, $count, $value, sub { my ($self, @res) = @_ });
  $promise = $self->lrem_p($key, $count, $value);

Remove elements from a list.

See L<https://redis.io/commands/lrem> for more information.

=head2 lset

  @res     = $self->lset($key, $index, $value);
  $self    = $self->lset($key, $index, $value, sub { my ($self, @res) = @_ });
  $promise = $self->lset_p($key, $index, $value);

Set the value of an element in a list by its index.

See L<https://redis.io/commands/lset> for more information.

=head2 ltrim

  @res     = $self->ltrim($key, $start, $stop);
  $self    = $self->ltrim($key, $start, $stop, sub { my ($self, @res) = @_ });
  $promise = $self->ltrim_p($key, $start, $stop);

Trim a list to the specified range.

See L<https://redis.io/commands/ltrim> for more information.

=head2 mget

  @res     = $self->mget($key [key ...]);
  $self    = $self->mget($key [key ...], sub { my ($self, @res) = @_ });
  $promise = $self->mget_p($key [key ...]);

Get the values of all the given keys.

See L<https://redis.io/commands/mget> for more information.

=head2 move

  @res     = $self->move($key, $db);
  $self    = $self->move($key, $db, sub { my ($self, @res) = @_ });
  $promise = $self->move_p($key, $db);

Move a key to another database.

See L<https://redis.io/commands/move> for more information.

=head2 mset

  @res     = $self->mset($key value [key value ...]);
  $self    = $self->mset($key value [key value ...], sub { my ($self, @res) = @_ });
  $promise = $self->mset_p($key value [key value ...]);

Set multiple keys to multiple values.

See L<https://redis.io/commands/mset> for more information.

=head2 msetnx

  @res     = $self->msetnx($key value [key value ...]);
  $self    = $self->msetnx($key value [key value ...], sub { my ($self, @res) = @_ });
  $promise = $self->msetnx_p($key value [key value ...]);

Set multiple keys to multiple values, only if none of the keys exist.

See L<https://redis.io/commands/msetnx> for more information.

=head2 persist

  @res     = $self->persist($key);
  $self    = $self->persist($key, sub { my ($self, @res) = @_ });
  $promise = $self->persist_p($key);

Remove the expiration from a key.

See L<https://redis.io/commands/persist> for more information.

=head2 ping

  @res     = $self->ping([message]);
  $self    = $self->ping([message], sub { my ($self, @res) = @_ });
  $promise = $self->ping_p([message]);

Ping the server.

See L<https://redis.io/commands/ping> for more information.

=head2 publish

  @res     = $self->publish($channel, $message);
  $self    = $self->publish($channel, $message, sub { my ($self, @res) = @_ });
  $promise = $self->publish_p($channel, $message);

Post a message to a channel.

See L<https://redis.io/commands/publish> for more information.

=head2 randomkey

  @res     = $self->randomkey();
  $self    = $self->randomkey(, sub { my ($self, @res) = @_ });
  $promise = $self->randomkey_p();

Return a random key from the keyspace.

See L<https://redis.io/commands/randomkey> for more information.

=head2 rename

  @res     = $self->rename($key, $newkey);
  $self    = $self->rename($key, $newkey, sub { my ($self, @res) = @_ });
  $promise = $self->rename_p($key, $newkey);

Rename a key.

See L<https://redis.io/commands/rename> for more information.

=head2 renamenx

  @res     = $self->renamenx($key, $newkey);
  $self    = $self->renamenx($key, $newkey, sub { my ($self, @res) = @_ });
  $promise = $self->renamenx_p($key, $newkey);

Rename a key, only if the new key does not exist.

See L<https://redis.io/commands/renamenx> for more information.

=head2 rpop

  @res     = $self->rpop($key);
  $self    = $self->rpop($key, sub { my ($self, @res) = @_ });
  $promise = $self->rpop_p($key);

Remove and get the last element in a list.

See L<https://redis.io/commands/rpop> for more information.

=head2 rpoplpush

  @res     = $self->rpoplpush($source, $destination);
  $self    = $self->rpoplpush($source, $destination, sub { my ($self, @res) = @_ });
  $promise = $self->rpoplpush_p($source, $destination);

Remove the last element in a list, prepend it to another list and return it.

See L<https://redis.io/commands/rpoplpush> for more information.

=head2 rpush

  @res     = $self->rpush($key, $value [value ...]);
  $self    = $self->rpush($key, $value [value ...], sub { my ($self, @res) = @_ });
  $promise = $self->rpush_p($key, $value [value ...]);

Append one or multiple values to a list.

See L<https://redis.io/commands/rpush> for more information.

=head2 rpushx

  @res     = $self->rpushx($key, $value);
  $self    = $self->rpushx($key, $value, sub { my ($self, @res) = @_ });
  $promise = $self->rpushx_p($key, $value);

Append a value to a list, only if the list exists.

See L<https://redis.io/commands/rpushx> for more information.

=head2 sadd

  @res     = $self->sadd($key, $member [member ...]);
  $self    = $self->sadd($key, $member [member ...], sub { my ($self, @res) = @_ });
  $promise = $self->sadd_p($key, $member [member ...]);

Add one or more members to a set.

See L<https://redis.io/commands/sadd> for more information.

=head2 scard

  @res     = $self->scard($key);
  $self    = $self->scard($key, sub { my ($self, @res) = @_ });
  $promise = $self->scard_p($key);

Get the number of members in a set.

See L<https://redis.io/commands/scard> for more information.

=head2 sdiff

  @res     = $self->sdiff($key [key ...]);
  $self    = $self->sdiff($key [key ...], sub { my ($self, @res) = @_ });
  $promise = $self->sdiff_p($key [key ...]);

Subtract multiple sets.

See L<https://redis.io/commands/sdiff> for more information.

=head2 sdiffstore

  @res     = $self->sdiffstore($destination, $key [key ...]);
  $self    = $self->sdiffstore($destination, $key [key ...], sub { my ($self, @res) = @_ });
  $promise = $self->sdiffstore_p($destination, $key [key ...]);

Subtract multiple sets and store the resulting set in a key.

See L<https://redis.io/commands/sdiffstore> for more information.

=head2 set

  @res     = $self->set($key, $value, [expiration EX seconds|PX milliseconds], [NX|XX]);
  $self    = $self->set($key, $value, [expiration EX seconds|PX milliseconds], [NX|XX], sub {my ($self, @res) = @_ });
  $promise = $self->set_p($key, $value, [expiration EX seconds|PX milliseconds], [NX|XX]);

Set the string value of a key.

See L<https://redis.io/commands/set> for more information.

=head2 setbit

  @res     = $self->setbit($key, $offset, $value);
  $self    = $self->setbit($key, $offset, $value, sub { my ($self, @res) = @_ });
  $promise = $self->setbit_p($key, $offset, $value);

Sets or clears the bit at offset in the string value stored at key.

See L<https://redis.io/commands/setbit> for more information.

=head2 setex

  @res     = $self->setex($key, $seconds, $value);
  $self    = $self->setex($key, $seconds, $value, sub { my ($self, @res) = @_ });
  $promise = $self->setex_p($key, $seconds, $value);

Set the value and expiration of a key.

See L<https://redis.io/commands/setex> for more information.

=head2 setnx

  @res     = $self->setnx($key, $value);
  $self    = $self->setnx($key, $value, sub { my ($self, @res) = @_ });
  $promise = $self->setnx_p($key, $value);

Set the value of a key, only if the key does not exist.

See L<https://redis.io/commands/setnx> for more information.

=head2 setrange

  @res     = $self->setrange($key, $offset, $value);
  $self    = $self->setrange($key, $offset, $value, sub { my ($self, @res) = @_ });
  $promise = $self->setrange_p($key, $offset, $value);

Overwrite part of a string at key starting at the specified offset.

See L<https://redis.io/commands/setrange> for more information.

=head2 sinter

  @res     = $self->sinter($key [key ...]);
  $self    = $self->sinter($key [key ...], sub { my ($self, @res) = @_ });
  $promise = $self->sinter_p($key [key ...]);

Intersect multiple sets.

See L<https://redis.io/commands/sinter> for more information.

=head2 sinterstore

  @res     = $self->sinterstore($destination, $key [key ...]);
  $self    = $self->sinterstore($destination, $key [key ...], sub { my ($self, @res) = @_ });
  $promise = $self->sinterstore_p($destination, $key [key ...]);

Intersect multiple sets and store the resulting set in a key.

See L<https://redis.io/commands/sinterstore> for more information.

=head2 sismember

  @res     = $self->sismember($key, $member);
  $self    = $self->sismember($key, $member, sub { my ($self, @res) = @_ });
  $promise = $self->sismember_p($key, $member);

Determine if a given value is a member of a set.

See L<https://redis.io/commands/sismember> for more information.

=head2 smembers

  @res     = $self->smembers($key);
  $self    = $self->smembers($key, sub { my ($self, @res) = @_ });
  $promise = $self->smembers_p($key);

Get all the members in a set.

See L<https://redis.io/commands/smembers> for more information.

=head2 smove

  @res     = $self->smove($source, $destination, $member);
  $self    = $self->smove($source, $destination, $member, sub { my ($self, @res) = @_ });
  $promise = $self->smove_p($source, $destination, $member);

Move a member from one set to another.

See L<https://redis.io/commands/smove> for more information.

=head2 sort

  @res     = $self->sort($key, [BY pattern], [LIMIT offset count], [GET pattern [GET pattern ...]], [ASC|DESC], [ALPHA], [STORE destination]);
  $self    = $self->sort($key, [BY pattern], [LIMIT offset count], [GET pattern [GET pattern ...]], [ASC|DESC], [ALPHA], [STORE destination], sub { my ($self, @res) = @_ });
  $promise = $self->sort_p($key, [BY pattern], [LIMIT offset count], [GET pattern [GET pattern ...]], [ASC|DESC], [ALPHA], [STORE destination]);

Sort the elements in a list, set or sorted set.

See L<https://redis.io/commands/sort> for more information.

=head2 spop

  @res     = $self->spop($key, [count]);
  $self    = $self->spop($key, [count], sub { my ($self, @res) = @_ });
  $promise = $self->spop_p($key, [count]);

Remove and return one or multiple random members from a set.

See L<https://redis.io/commands/spop> for more information.

=head2 srandmember

  @res     = $self->srandmember($key, [count]);
  $self    = $self->srandmember($key, [count], sub { my ($self, @res) = @_ });
  $promise = $self->srandmember_p($key, [count]);

Get one or multiple random members from a set.

See L<https://redis.io/commands/srandmember> for more information.

=head2 srem

  @res     = $self->srem($key, $member [member ...]);
  $self    = $self->srem($key, $member [member ...], sub { my ($self, @res) = @_ });
  $promise = $self->srem_p($key, $member [member ...]);

Remove one or more members from a set.

See L<https://redis.io/commands/srem> for more information.

=head2 strlen

  @res     = $self->strlen($key);
  $self    = $self->strlen($key, sub { my ($self, @res) = @_ });
  $promise = $self->strlen_p($key);

Get the length of the value stored in a key.

See L<https://redis.io/commands/strlen> for more information.

=head2 sunion

  @res     = $self->sunion($key [key ...]);
  $self    = $self->sunion($key [key ...], sub { my ($self, @res) = @_ });
  $promise = $self->sunion_p($key [key ...]);

Add multiple sets.

See L<https://redis.io/commands/sunion> for more information.

=head2 sunionstore

  @res     = $self->sunionstore($destination, $key [key ...]);
  $self    = $self->sunionstore($destination, $key [key ...], sub { my ($self, @res) = @_ });
  $promise = $self->sunionstore_p($destination, $key [key ...]);

Add multiple sets and store the resulting set in a key.

See L<https://redis.io/commands/sunionstore> for more information.

=head2 ttl

  @res     = $self->ttl($key);
  $self    = $self->ttl($key, sub { my ($self, @res) = @_ });
  $promise = $self->ttl_p($key);

Get the time to live for a key.

See L<https://redis.io/commands/ttl> for more information.

=head2 type

  @res     = $self->type($key);
  $self    = $self->type($key, sub { my ($self, @res) = @_ });
  $promise = $self->type_p($key);

Determine the type stored at key.

See L<https://redis.io/commands/type> for more information.

=head2 zadd

  @res     = $self->zadd($key, [NX|XX], [CH], [INCR], $score member [score member ...]);
  $self    = $self->zadd($key, [NX|XX], [CH], [INCR], $score member [score member ...], sub {my ($self, @res) = @_ });
  $promise = $self->zadd_p($key, [NX|XX], [CH], [INCR], $score member [score member ...]);

Add one or more members to a sorted set, or update its score if it already exists.

See L<https://redis.io/commands/zadd> for more information.

=head2 zcard

  @res     = $self->zcard($key);
  $self    = $self->zcard($key, sub { my ($self, @res) = @_ });
  $promise = $self->zcard_p($key);

Get the number of members in a sorted set.

See L<https://redis.io/commands/zcard> for more information.

=head2 zcount

  @res     = $self->zcount($key, $min, $max);
  $self    = $self->zcount($key, $min, $max, sub { my ($self, @res) = @_ });
  $promise = $self->zcount_p($key, $min, $max);

Count the members in a sorted set with scores within the given values.

See L<https://redis.io/commands/zcount> for more information.

=head2 zincrby

  @res     = $self->zincrby($key, $increment, $member);
  $self    = $self->zincrby($key, $increment, $member, sub { my ($self, @res) = @_ });
  $promise = $self->zincrby_p($key, $increment, $member);

Increment the score of a member in a sorted set.

See L<https://redis.io/commands/zincrby> for more information.

=head2 zinterstore

  @res     = $self->zinterstore($destination, $numkeys, $key [key ...], [WEIGHTS weight [weight ...]], [AGGREGATE SUM|MIN|MAX]);
  $self    = $self->zinterstore($destination, $numkeys, $key [key ...], [WEIGHTS weight [weight ...]], [AGGREGATE SUM|MIN|MAX], sub { my ($self, @res) = @_ });
  $promise = $self->zinterstore_p($destination, $numkeys, $key [key ...], [WEIGHTS weight [weight ...]], [AGGREGATE SUM|MIN|MAX]);

Intersect multiple sorted sets and store the resulting sorted set in a new key.

See L<https://redis.io/commands/zinterstore> for more information.

=head2 zrange

  @res     = $self->zrange($key, $start, $stop, [WITHSCORES]);
  $self    = $self->zrange($key, $start, $stop, [WITHSCORES], sub { my ($self, @res) = @_ });
  $promise = $self->zrange_p($key, $start, $stop, [WITHSCORES]);

Return a range of members in a sorted set, by index.

See L<https://redis.io/commands/zrange> for more information.

=head2 zrangebyscore

  @res     = $self->zrangebyscore($key, $min, $max, [WITHSCORES], [LIMIT offset count]);
  $self    = $self->zrangebyscore($key, $min, $max, [WITHSCORES], [LIMIT offset count], sub {my ($self, @res) = @_ });
  $promise = $self->zrangebyscore_p($key, $min, $max, [WITHSCORES], [LIMIT offset count]);

Return a range of members in a sorted set, by score.

See L<https://redis.io/commands/zrangebyscore> for more information.

=head2 zrank

  @res     = $self->zrank($key, $member);
  $self    = $self->zrank($key, $member, sub { my ($self, @res) = @_ });
  $promise = $self->zrank_p($key, $member);

Determine the index of a member in a sorted set.

See L<https://redis.io/commands/zrank> for more information.

=head2 zrem

  @res     = $self->zrem($key, $member [member ...]);
  $self    = $self->zrem($key, $member [member ...], sub { my ($self, @res) = @_ });
  $promise = $self->zrem_p($key, $member [member ...]);

Remove one or more members from a sorted set.

See L<https://redis.io/commands/zrem> for more information.

=head2 zremrangebyrank

  @res     = $self->zremrangebyrank($key, $start, $stop);
  $self    = $self->zremrangebyrank($key, $start, $stop, sub { my ($self, @res) = @_ });
  $promise = $self->zremrangebyrank_p($key, $start, $stop);

Remove all members in a sorted set within the given indexes.

See L<https://redis.io/commands/zremrangebyrank> for more information.

=head2 zremrangebyscore

  @res     = $self->zremrangebyscore($key, $min, $max);
  $self    = $self->zremrangebyscore($key, $min, $max, sub { my ($self, @res) = @_ });
  $promise = $self->zremrangebyscore_p($key, $min, $max);

Remove all members in a sorted set within the given scores.

See L<https://redis.io/commands/zremrangebyscore> for more information.

=head2 zrevrange

  @res     = $self->zrevrange($key, $start, $stop, [WITHSCORES]);
  $self    = $self->zrevrange($key, $start, $stop, [WITHSCORES], sub { my ($self, @res) = @_ });
  $promise = $self->zrevrange_p($key, $start, $stop, [WITHSCORES]);

Return a range of members in a sorted set, by index, with scores ordered from high to low.

See L<https://redis.io/commands/zrevrange> for more information.

=head2 zrevrangebyscore

  @res     = $self->zrevrangebyscore($key, $max, $min, [WITHSCORES], [LIMIT offset count]);
  $self    = $self->zrevrangebyscore($key, $max, $min, [WITHSCORES], [LIMIT offset count], sub { my ($self, @res) = @_ });
  $promise = $self->zrevrangebyscore_p($key, $max, $min, [WITHSCORES], [LIMIT offset count]);

Return a range of members in a sorted set, by score, with scores ordered from high to low.

See L<https://redis.io/commands/zrevrangebyscore> for more information.

=head2 zrevrank

  @res     = $self->zrevrank($key, $member);
  $self    = $self->zrevrank($key, $member, sub { my ($self, @res) = @_ });
  $promise = $self->zrevrank_p($key, $member);

Determine the index of a member in a sorted set, with scores ordered from high to low.

See L<https://redis.io/commands/zrevrank> for more information.

=head2 zscore

  @res     = $self->zscore($key, $member);
  $self    = $self->zscore($key, $member, sub { my ($self, @res) = @_ });
  $promise = $self->zscore_p($key, $member);

Get the score associated with the given member in a sorted set.

See L<https://redis.io/commands/zscore> for more information.

=head2 zunionstore

  @res     = $self->zunionstore($destination, $numkeys, $key [key ...], [WEIGHTS weight [weight ...]], [AGGREGATE SUM|MIN|MAX]);
  $self    = $self->zunionstore($destination, $numkeys, $key [key ...], [WEIGHTS weight [weight ...]], [AGGREGATE SUM|MIN|MAX], sub { my ($self, @res) = @_ });
  $promise = $self->zunionstore_p($destination, $numkeys, $key [key ...], [WEIGHTS weight [weight ...]], [AGGREGATE SUM|MIN|MAX]);

Add multiple sorted sets and store the resulting sorted set in a new key.

See L<https://redis.io/commands/zunionstore> for more information.

=head1 SEE ALSO

L<Mojo::Redis>.

=cut
