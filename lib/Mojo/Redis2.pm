package Mojo::Redis2;

=head1 NAME

Mojo::Redis2 - Pure-Perl non-blocking I/O Redis driver

=head1 VERSION

0.06

=head1 DESCRIPTION

THIS MODULE IS UNDER DEVELOPMENT! FEEDBACK WANTED!

L<Mojo::Redis2> is a pure-Perl non-blocking I/O L<Redis|http://redis.io>
driver for the L<Mojolicious> real-time framework.

=over

Redis is an open source, BSD licensed, advanced key-value cache and store.
It is often referred to as a data structure server since keys can contain
strings, hashes, lists, sets, sorted sets, bitmaps and hyperloglogs.
- L<http://redis.io>.

=back

Features:

=over 4

=item * Blocking support

L<Mojo::Redis2> support blocking methods. NOTE: Calling non-blocking and
blocking methods are supported on the same object, but might create a new
connection to the server.

=item * Error handling that makes sense

L<Mojo::Redis> was unable to report back errors that was bound to an operation.
L<Mojo::Redis2> on the other hand always make sure each callback receive an
error message on error.

=item * One object for different operations

L<Mojo::Redis> had only one connection, so it could not do more than on
blocking operation on the server side at the time (such as BLPOP,
SUBSCRIBE, ...). This object creates new connections pr. blocking operation
which makes it easier to avoid "blocking" bugs.

=back

=head1 SYNOPSIS

=head2 Blocking

  use Mojo::Redis2;
  my $redis = Mojo::Redis2->new;

  # Will die() on error.
  $res = $redis->set(foo => "42"); # $res = OK
  $res = $redis->get("foo");       # $res = 42

=head2 Non-blocking

  Mojo::IOLoop->delay(
    sub {
      my ($delay) = @_;
      $redis->ping($delay->begin)->get("foo", $delay->begin);
    },
    sub {
      my ($delay, $ping_err, $ping, $get_err, $get) = @_;
      # On error: $ping_err and $get_err is set to a string
      # On success: $ping = "PONG", $get = "42";
    },
  );

=head2 Pub/sub

L<Mojo::Redis2> can L</subscribe> and re-use the same object to C<publish> or
run other Redis commands, since it can keep track of multiple connections to
the same Redis server. It will also re-use the same connection when you
(p)subscribe multiple times.

  $self->on(message => sub {
    my ($self, $message, $channel) = @_;
  });

  $self->subscribe("some:channel" => sub {
    my ($self, $err) = @_;

    return $self->publish("myapp:errors" => $err) if $err;
    return $self->incr("subscribed:to:some:channel");
  });

=head2 Mojolicious app

  use Mojolicious::Lite;

  helper redis => sub { shift->stash->{redis} ||= Mojo::Redis2->new; };

  get '/' => sub {
    my $c = shift;

    $c->delay(
      sub {
        my ($delay) = @_;
        $c->redis->get('some:message', $delay->begin);
      },
      sub {
        my ($delay, $err, $message) = @_;
        $c->render(json => { error => $err, message => $message });
      },
    );
  };

  app->start;

=head2 Error handling

C<$err> in this document is a string containing an error message or
empty string on success.

=cut

use Mojo::Base 'Mojo::EventEmitter';
use Mojo::IOLoop;
use Mojo::URL;
use Mojo::Util;
use Carp ();
use constant DEBUG => $ENV{MOJO_REDIS_DEBUG} || 0;
use constant SERVER_DEBUG => $ENV{MOJO_REDIS_SERVER_DEBUG} || 0;
use constant DEFAULT_PORT => 6379;

our $VERSION = '0.06';

my %SERVER;
my $PROTOCOL_CLASS = do {
  my $class = $ENV{MOJO_REDIS_PROTOCOL} ||= eval "require Protocol::Redis::XS; 'Protocol::Redis::XS'" || 'Protocol::Redis';
  eval "require $class; 1" or die $@;
  $class;
};

=head1 EVENTS

=head2 connection

  $self->on(error => sub { my ($self, $info) = @_; ... });

Emitted when a new connection has been established. C<$info> is a hash ref
with:

  {
    group => $str, # basic, blpop, brpop, brpoplpush, publish, ...
    id => $connection_id,
    nb => $bool, # blocking/non-blocking
  }

Note: The structure of C<$info> is EXPERIMENTAL.

=head2 error

  $self->on(error => sub { my ($self, $err) = @_; ... });

Emitted if an error occurs that can't be associated with an operation.

=head2 message

  $self->on(message => sub {
    my ($self, $message, $channel) = @_;
  });

Emitted when a C<$message> is received on a C<$channel> after it has been
L<subscribed|/subscribe> to.

=head2 pmessage

  $self->on(pmessage => sub {
    my ($self, $message, $channel, $pattern) = @_;
  });

Emitted when a C<$message> is received on a C<$channel> matching a
C<$pattern>, after it has been L<subscribed|/psubscribe> to.

=head1 ATTRIBUTES

=head2 encoding

  $str = $self->encoding;
  $self = $self->encoding('UTF-8');

Holds the encoding using for data from/to Redis. Default is UTF-8.

=head2 protocol

  $obj = $self->protocol;
  $self = $self->protocol($obj);

Holds an object used to parse/generate Redis messages.
Defaults to L<Protocol::Redis::XS> or L<Protocol::Redis>.

L<Protocol::Redis::XS> need to be installed manually.

=cut

has encoding => 'UTF-8';
has protocol => sub { $PROTOCOL_CLASS->new(api => 1); };

=head2 url

  $url = $self->url;

Holds a L<Mojo::URL> object with the location to the Redis server. Default
is C<MOJO_REDIS_URL> or "redis://localhost:6379". The L</url> need to be set
in constructor. Examples:

  Mojo::Redis2->new(url => "redis://x:$auth_key\@$server:$port/$database_index");
  Mojo::Redis2->new(url => "redis://10.0.0.42:6379");
  Mojo::Redis2->new(url => "redis://10.0.0.42:6379/1");
  Mojo::Redis2->new(url => "redis://x:s3cret\@10.0.0.42:6379/1");

=cut

sub url { $_[0]->{url} ||= Mojo::URL->new($ENV{MOJO_REDIS_URL} || 'redis://localhost:6379'); }

=head1 METHODS

In addition to the methods listed in this module, you can call these Redis
methods on C<$self>:

append, echo, decr, decrby,
del, exists, expire, expireat, get, getbit,
getrange, getset, hdel, hexists, hget, hgetall,
hincrby, hkeys, hlen, hmget, hmset, hset,
hsetnx, hvals, incr, incrby, keys, lindex,
linsert, llen, lpop, lpush, lpushx, lrange,
lrem, lset, ltrim, mget, move, mset,
msetnx, persist, ping, publish, randomkey, rename,
renamenx, rpop, rpoplpush, rpush, rpushx, sadd,
scard, sdiff, sdiffstore, set, setbit, setex,
setnx, setrange, sinter, sinterstore, sismember, smembers,
smove, sort, spop, srandmember, srem, strlen,
sunion, sunionstore, ttl, type, zadd, zcard,
zcount, zincrby, zinterstore, zrange, zrangebyscore, zrank,
zrem, zremrangebyrank, zremrangebyscore, zrevrange, zrevrangebyscore, zrevrank,
zscore and zunionstore.

See L<http://redis.io/commands> for details.

=head2 new

  $self = Mojo::Redis2->new(...);

Object constructor. Makes sure L</url> is an object.

=cut

sub new {
  my $self = shift->SUPER::new(@_);

  if ($self->{url} and ref $self->{url} eq '') {
    $self->{url} = "redis://$self->{url}" unless $self->{url} =~ /^redis:/;
    $self->{url} = Mojo::URL->new($self->{url});
  }

  $self;
}

=head2 blpop

  $self = $self->blpop(@keys, $timeout, sub { my ($self, $res) = @_; });

This method will issue the BLPOP command on the Redis server, but in its
own connection. This means that C<$self> can still be used to run other
L<commands|/METHODS> instead of being blocking.

Note: This method will only work in a non-blocking environment.

See also L<http://redis.io/commands/blpop>.

=head2 brpoplpush

  $self = $self->brpoplpush($from => $to, $timeout, sub { my ($self, $res) = @_; });

Follows the same API as L</blpop>.
See also L<http://redis.io/commands/brpoplpush>.

=head2 brpop

  $self = $self->brpop(@keys, $timeout, sub { my ($self, $res) = @_; });

Follows the same API as L</blpop>.
See also L<http://redis.io/commands/brpop>.

=cut

sub blpop { shift->_execute(blpop => BLPOP => @_); }
sub brpop { shift->_execute(brpop => BRPOP => @_); }
sub brpoplpush { shift->_execute(brpoplpush => BRPOPLPUSH => @_); }

=head2 bulk

  $obj = $self->bulk;

Returns a L<Mojo::Redis2::Bulk> object which can be used to group Redis
operations.

=cut

sub bulk {
  my $self = shift;
  require Mojo::Redis2::Bulk;
  Mojo::Redis2::Bulk->new(_redis => $self);
}

=head2 client

  $self->client->$method(@args);

Run "CLIENT" commands using L<Mojo::Redis2::Client>.

=cut

sub client {
  my $self = shift;
  require Mojo::Redis2::Client;
  Mojo::Redis2::Client->new(_redis => $self);
}

=head2 multi

  $txn = $self->multi;

This method does not perform the "MULTI" Redis command, but returns a
L<Mojo::Redis2::Transaction> object instead.

The L<Mojo::Redis2::Transaction> object is a subclass of L<Mojo::Redis2>,
which will run all the Redis commands inside a transaction.

=cut

sub multi {
  my $self = shift;
  my @attributes = qw( encoding protocol url );
  require Mojo::Redis2::Transaction;
  Mojo::Redis2::Transaction->new(map { $_ => $self->$_ } @attributes);
}

=head2 psubscribe

  $self = $self->psubscribe(@patterns, sub { my ($self, $err, $res) = @_; ... });

Used to subscribe to channels that match C<@patterns>. Messages arriving over a
matching channel name will result in L</pmessage> events.

See L<http://redis.io/topics/pubsub> for details.

=head2 subscribe

  $self = $self->subscribe(@channels, sub { my ($self, $err, $res) = @_; ... });

Used to subscribe to C<@channels>. Messages arriving over a channel will
result in L</message> events.

See L<http://redis.io/topics/pubsub> for details.

=cut

sub psubscribe {
  my $cb = ref $_[-1] eq 'CODE' ? pop : sub {};
  shift->_execute(pubsub => PSUBSCRIBE => @_, $cb);
}

sub subscribe {
  my $cb = ref $_[-1] eq 'CODE' ? pop : sub {};
  shift->_execute(pubsub => SUBSCRIBE => @_, $cb);
}

=head2 start_server

  $config = $class->start_server(\%config);

This method will try to start an instance of the Redis server or C<die()>
trying. L</start_server> is a hack meant to be used in unit tests. (Any
improvements are welcome)

The returned C<$config> is a hash-ref with these values, unless specified
in the input C<%config>.

=over 4

=item * bind: "localhost"

=item * port: A randomly picked port

=back

The L<MOJO_REDIS_URL|/url> environment variable is also set unless defined
up front.

=cut

sub start_server {
  my $class = shift;
  my $config = shift || {};

  return \%SERVER if $SERVER{pid} and kill 0, $SERVER{pid};

  $config->{bind} ||= 'localhost';
  $config->{daemonize} ||= 'no';
  $config->{databases} ||= 16;
  $config->{loglevel} ||= SERVER_DEBUG ? 'verbose' : 'warning';
  $config->{port} ||= Mojo::IOLoop::Server->generate_port;
  $config->{rdbchecksum} ||= 'no';
  $config->{requirepass} ||= '';
  $config->{stop_writes_on_bgsave_error} ||= 'no';
  $config->{syslog_enabled} ||= 'no';
  $config->{tcp_keepalive} ||= 0;

  pipe my $READ, my $WRITE or die $!;
  require Mojo::Asset::File;
  my $cfg = Mojo::Asset::File->new;

  while (my($key, $value) = each %$config) {
    $key =~ s!_!-!g;
    warn "[Redis::Server] config $key $value\n" if SERVER_DEBUG;
    $cfg->add_chunk("$key $value\n") if length $value;
  }

  $config->{config_file} = $cfg->path .'-redis.conf';
  $cfg->move_to($config->{config_file});

  if ($config->{pid} = fork) { # parent
    close $WRITE;

    if (my $err = readline $READ || $class->_server_status($config)) {
      warn "[Redis::Server] failed: $err\n" if SERVER_DEBUG;
      waitpid $config->{pid}, 0; # wait for hanging child process
      die $err;
    }

    %SERVER = %$config;
    $ENV{MOJO_REDIS_URL} //= sprintf 'redis://x:%s@%s:%s/', map { $_ // '' } @$config{qw( requirepass bind port )};
    warn "[Redis::Server] MOJO_REDIS_URL=$ENV{MOJO_REDIS_URL}\n" if SERVER_DEBUG;
    return \%SERVER;
  }

  no warnings;
  exec +($ENV{REDIS_SERVER_BIN} || 'redis-server'), $cfg->path;
  print $WRITE "Could not start Redis server: $!\n";
  exit;
}

sub DESTROY { $_[0]->{destroy} = 1; $_[0]->_cleanup; }

sub _basic_operations {
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
  'zremrangebyscore', 'zrevrange',   'zrevrangebyscore', 'zrevrank', 'zscore',   'zunionstore',
}

sub _blocking_group { 'blocking' }

sub _cleanup {
  my $self = shift;
  my $connections = delete $self->{connections};

  delete $self->{pid};

  for my $c (values %$connections) {
    my $loop = $self->_loop($c->{nb}) or next;
    $loop->remove($c->{id}) if $c->{id};
    $self->$_('Premature connection close', []) for grep { $_ } map { $_->[0] } @{ $c->{waiting} };
  }
}

sub _connect {
  my ($self, $c) = @_;
  my $url = $self->url;
  my $db = $url->path->[0];
  my @userinfo = split /:/, +($url->userinfo // '');

  Scalar::Util::weaken($self);
  $c->{name} = $url->clone->userinfo('')->query({ g => $c->{group} })->to_string if DEBUG;
  $c->{id} = $self->_loop($c->{nb})->client(
    { address => $url->host, port => $url->port || DEFAULT_PORT },
    sub {
      my ($loop, $err, $stream) = @_;

      if ($err) {
        delete $c->{id};
        return $self->_error($c, $err);
      }

      warn "[$c->{name}] connected\n" if DEBUG;

      $stream->timeout(0);
      $stream->on(close => sub { $self->_error($c) });
      $stream->on(error => sub { $self and $self->_error($c, $_[1]) });
      $stream->on(read => sub { $self->_read($c, $_[1]) });

      # NOTE: unshift() will cause AUTH to be sent before SELECT
      unshift @{ $c->{queue} }, [ undef, SELECT => $db ] if $db;
      unshift @{ $c->{queue} }, [ undef, AUTH => $userinfo[1] ] if length $userinfo[1];

      $self->emit_safe(connection => { map { $_ => $c->{$_} } qw( group id nb ) });
      $self->_dequeue($c);
    },
  );

  $self;
}

sub _dequeue {
  my ($self, $c) = @_;
  my $loop = $self->_loop($c->{nb});
  my $stream = $loop->stream($c->{id}) or return $self;
  my $queue = $c->{queue};
  my $buf;

  if (!$queue->[0]) {
    return $self;
  }

  # Make sure connection has not been corrupted while event loop was stopped
  if (!$loop->is_running and $stream->is_readable) {
    $stream->close;
    return $self;
  }

  push @{ $c->{waiting} }, shift @$queue;
  $buf = $self->_op_to_command($c->{waiting}[-1]);
  do { local $_ = $buf; s!\r\n!\\r\\n!g; warn "[$c->{name}] <<< ($_)\n" } if DEBUG;
  $stream->write($buf);
  $self;
}

sub _error {
  my ($self, $c, $err) = @_;
  my $waiting = $c->{waiting} || [];

  warn "[$c->{name}] !!! @{[$err // 'close']}\n" if DEBUG;

  return if $self->{destroy};
  return $self->_connect($c) unless defined $err;
  return $self->emit_safe(error => $err) unless @$waiting;
  return $self->$_($err, []) for grep { $_ } map { $_->[0] } @$waiting;
}

sub _execute {
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  my ($self, $group, @cmd) = @_;

  $self->_cleanup unless ($self->{pid} //= $$) eq $$; # TODO: Fork safety

  if ($cb) {
    my $c = $self->{connections}{$group} ||= { nb => 1, group => $group };
    push @{ $c->{queue} }, [$cb, @cmd];
    return $self->_connect($c) unless $c->{id};
    return $self->_dequeue($c);
  }
  else {
    my $c = $self->{connections}{$self->_blocking_group} ||= { nb => 0, group => $self->_blocking_group };
    my ($err, $res);

    push @{ $c->{queue} }, [sub { shift->_loop(0)->stop; ($err, $res) = @_; }, @cmd];
    $c->{id} ? $self->_dequeue($c) : $self->_connect($c);
    $self->_loop(0)->start;
    die "[@cmd] $err" if $err;
    return $res;
  }
}

sub _loop {
  $_[1] ? Mojo::IOLoop->singleton : ($_[0]->{ioloop} ||= Mojo::IOLoop->new);
}

sub _op_to_command {
  my ($self, $op) = @_;
  my ($i, @data);

  for my $token (@$op) {
    next unless $i++;
    $token = Mojo::Util::encode($self->encoding, $token) if $self->encoding;
    push @data, {type => '$', data => $token};
  }

  $self->protocol->encode({type => '*', data => \@data});
}

sub _read {
  my ($self, $c, $buf) = @_;
  my $protocol = $self->protocol;
  my $event;

  do { local $_ = $buf; s!\r\n!\\r\\n!g; warn "[$c->{name}] >>> ($_)\n" } if DEBUG;
  $protocol->parse($buf);

  MESSAGE:
  while (my $message = $protocol->get_message) {
    my $data = $self->_reencode_message($message);
    my $op = shift @{ $c->{waiting} || [] };
    my $cb = $op->[0];

    if (ref $data eq 'SCALAR') {
      $self->$cb($$data, []) if $cb;
    }
    elsif (ref $data eq 'ARRAY' and @$data and $data->[0] =~ /^(p?message)$/i) {
      $event = shift @$data;
      $self->emit($event => reverse @$data);
    }
    else {
      $self->$cb('', $data) if $cb;
    }

    $self->_dequeue($c);
  }
}

sub _reencode_message {
  my ($self, $message) = @_;
  my ($type, $data) = @{$message}{qw( type data )};

  if ($type ne '*' and $self->encoding and $data) {
    $data = Encode::decode($self->encoding, $data);
  }

  if ($type eq '-') {
    return \ $data;
  }
  elsif ($type ne '*') {
    return $data;
  }
  else {
    return [ map { $self->_reencode_message($_); } @$data ];
  }
}

sub _server_status {
  my ($class, $config) = @_;
  my $guard = 100;
  my $err;

  require IO::Socket::INET;
  require Time::HiRes;

  while($guard--) {
    Time::HiRes::usleep(10e3);
    return '' if IO::Socket::INET->new(PeerAddr => $config->{bind}, PeerPort => $config->{port}, Proto => 'tcp', Timeout => 10);
    return 'Redis server failed to start' if waitpid $config->{pid}, 0;
  }

  return 'Redis server has unknown status';
}

sub _stop_server {
  my $class = shift;
  my $config = shift || \%SERVER;

  if ($config->{config_file} and -r $config->{config_file}) {
    kill 15, $config->{pid} if $config->{pid};
    unlink $config->{config_file};
  }

  return $class;
}

for my $method (__PACKAGE__->_basic_operations) {
  my $op = uc $method;
  eval "sub $method { shift->_execute(basic => $op => \@_); }; 1" or die $@;
}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

END { __PACKAGE__->_stop_server; }

1;
