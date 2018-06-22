package Mojo::Redis::Connection;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::IOLoop;
use Mojo::Promise;

use constant DEBUG => $ENV{MOJO_REDIS_DEBUG};

has loop     => sub { Carp::confess('loop is required in constructor') };
has protocol => sub { Carp::confess('protocol is required in constructor') };
has url      => sub { Carp::confess('url is required in constructor') };

sub disconnect {
  my $self = shift;
  $self->{stream}->close if $self->{stream};
  return $self;
}

sub is_connected { shift->{stream} ? 1 : 0 }

sub write {
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  my $self = shift;

  push @{$self->{write}},
    [$self->protocol->encode({type => '*', data => [map { +{type => '$', data => $_} } @_]}), $cb];

  Scalar::Util::weaken($self);
  $self->{stream} ? $self->loop->next_tick(sub { $self->_write }) : $self->_connect;
  return $self;
}

sub write_p {
  my $self = shift;
  my $p    = Mojo::Promise->new;

  push @{$self->{write}}, [$self->protocol->encode({type => '*', data => [map { +{type => '$', data => $_} } @_]}), $p];

  Scalar::Util::weaken($self);
  $self->{stream} ? $self->loop->next_tick(sub { $self->_write }) : $self->_connect;
  return $p;
}

sub _connect {
  my $self = shift;
  return $self if $self->{id};    # Connecting
  Scalar::Util::weaken($self);

  $self->protocol->on_message(sub {
    my ($protocol, $message) = @_;
    my $h = shift @{$self->{waiting} || []};

    if (ref $h eq 'CODE') {
      $self->$h('', $message->{data});
    }
    elsif ($h) {
      $h->resolve($message->{data});
    }
    else {
      $self->emit(message => $message);
    }

    $self->_write;
  });

  my $url = $self->url;
  my $db  = $url->path->[0];
  $self->{id} = $self->loop->client(
    {address => $url->host, port => $url->port || 6379},
    sub {
      my ($loop, $err, $stream) = @_;

      unless ($self) {
        delete $self->{$_} for qw(id stream);
        $stream->close;
        return;
      }

      my $close_cb = $self->_on_close_cb;
      return $self->$close_cb($err) if $err;

      $stream->timeout(0);
      $stream->on(close => $close_cb);
      $stream->on(error => $close_cb);
      $stream->on(read  => $self->_on_read_cb);

      unshift @{$self->{write}}, ["SELECT $db"] if length $db;
      unshift @{$self->{write}}, ["AUTH @{[$url->password]}"] if length $url->password;

      $self->{stream} = $stream;
      $self->emit('connect');
      $self->_write;
    },
  );

  warn "[$self->{id}] CONNECTING $url (blocking=@{[$self->_loop_is_singleton ? 0 : 1]})\n" if DEBUG;
  return $self;
}

sub _loop_is_singleton { shift->loop eq Mojo::IOLoop->singleton }

sub _on_close_cb {
  my $self = shift;

  Scalar::Util::weaken($self);
  return sub {
    return unless $self;
    my ($stream, $err) = @_;
    delete $self->{$_} for qw(id stream);
    $self->emit(error => $err) if $err;
    warn qq([$self->{id}] @{[$err ? "ERROR $err" : "CLOSED"]}\n) if DEBUG;
  };
}

sub _on_read_cb {
  my $self = shift;

  Scalar::Util::weaken($self);
  return sub {
    my ($stream, $chunk) = @_;
    do { local $_ = $chunk; s!\r\n!\\r\\n!g; warn "[$self->{id}] >>> ($_)\n" } if DEBUG;
    $self->protocol->parse($chunk);
  };
}

sub _write {
  my $self  = shift;
  my $loop  = $self->loop;
  my $queue = $self->{write} || [];

  return unless @$queue;

  # Make sure connection has not been corrupted while event loop was stopped
  if (!$self->loop->is_running and $self->{stream}->is_readable) {
    delete($self->{stream})->close;
    delete $self->{id};
    $self->_connect;
    return $self;
  }

  my $op = shift @$queue;
  do { local $_ = $op->[0]; s!\r\n!\\r\\n!g; warn "[$self->{id}] <<< ($_)\n" } if DEBUG;
  push @{$self->{waiting}}, $op->[1] || sub { shift->emit(error => $_[1]) if $_[1] };
  $self->{stream}->write($op->[0]);
}

1;

=encoding utf8

=head1 NAME

Mojo::Redis::Connection - Low level connection class for talking to Redis

=head1 SYNOPSIS

  use Mojo::Redis::Connection;

  my $conn = Mojo::Redis::Connection->new(
               loop     => Mojo::IOLoop->singleton,
               protocol => Protocol::Redis::XS->new(api => 1),
               url      => Mojo::URL->new("redis://localhost"),
             );

  $conn->write_p("GET some_key")->then(sub { print "some_key=$_[0]" })->wait;

=head1 DESCRIPTION

L<Mojo::Redis::Connection> is a low level driver for writing and reading data
from a Redis server.

You probably want to use L<Mojo::Redis> instead of this class.

=head1 ATTRIBUTES

=head2 loop

  $loop = $self->loop;
  $self = $self->loop(Mojo::IOLoop->new);

Holds an instance of L<Mojo::IOLoop>.

=head2 protocol

  $protocol = $self->protocol;
  $self = $self->protocol(Protocol::Redis::XS->new(api => 1));

Holds a protocol object, such as L<Protocol::Redis> that is used to generate
and parse Redis messages.

=head2 url

  $url = $self->url;
  $self = $self->url(Protocol::Redis::XS->new(api => 1));

=head1 METHODS

=head2 disconnect

  $self = $self->disconnect;

Used to disconnect from the Redis server.

=head2 is_connected

  $bool = $self->is_connected;

True if a connection to the Redis server is established.

=head2 write

  $self = $self->write($bytes);
  $self = $self->write($bytes, sub { my ($self, @res) = @_; });

Will write C<$bytes> to the Redis server and establish a connection if not
already connected. The callback will receive the response from the Redis server
after it is parsed by L</protocol>.

=head2 write_p

  $p = $self->write_p($bytes)->then(sub { my @res = @_ });

Same as L</write>, but returns a L<Mojo::Promise>.

=head1 SEE ALSO

L<Mojo::Redis>

=cut
