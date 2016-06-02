package Mojo::Redis2::Cursor;
use Mojo::Base '-base';

use Carp 'croak';
use Scalar::Util 'looks_like_number';

has command => 'SCAN';
has 'redis';
has key     => '';
has _args   => sub { [] };
has _cursor => 0;

sub again {
  my $self = shift;
  $self->_cursor(0);
  delete $self->{_finished};
  return $self;
}

sub finished { !!shift->{_finished} }

sub hgetall {
  my $cur = shift->_clone('HSCAN', shift);
  return $cur->slurp(@_);
}

sub hkeys {
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  my $cur = shift->_clone('HSCAN' => @_);
  my $wrapper = sub {
    my $keys = [grep { $a = !$a } @{$_[2] || []}];
    return $cur->$cb($_[1], $keys);
  };
  my $resp = $cur->slurp($cb ? ($wrapper) : ());
  return $resp if $cb;
  $cb = sub { $_[2] };
  return $wrapper->(undef, '', $resp);
}

sub keys {
  my $cur = shift->_clone('SCAN');
  unshift @_, 'MATCH' if $_[0] && !ref $_[0];
  return $cur->slurp(@_);
}

sub new {
  my $self = shift->SUPER::new();
  $self->command(my $command = shift);
  $self->key(shift) if $command ne 'SCAN';
  croak 'ERR Should not specify cursor value manualy.'
    if looks_like_number $_[0];
  $self->_args(\@_) if @_;
  return $self;
}

sub next {
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  my $self = shift;

  return undef if $self->{_finished};

  my $args = @_ ? $self->_args(\@_)->{_args} : $self->_args;
  my $wrapper = sub {
    my (undef, $err, $resp) = @_;
    $self->_cursor(my $cur = $resp->[0] // 0);
    $self->{_finished} = 1 if $cur == 0;
    return $self->$cb($err, $resp->[1]);
  };

  my $command = $self->command;
  my $resp    = $self->redis->_execute(
    basic => $command,
    $command ne 'SCAN' ? ($self->key) : (), $self->_cursor, @$args,
    $cb ? ($wrapper) : ()
  );
  return $resp if $cb;
  $cb = sub { $_[2] };
  return $wrapper->(undef, '', $resp);
}

sub slurp {
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  my $self = shift;

  my $list = [];

  # non-blocking
  if ($cb) {

    # __SUB__ available only from 5.16
    my $wrapper;
    $wrapper = sub {
      push @$list, @{$_[2] // []};
      return $self->$cb($_[1], $list) if $_[0]->{_finished};
      $self->next($wrapper);
    };
    return $self->next(@_ => $wrapper);
  }

  # blocking
  else {
    while (my $r = $self->next(@_)) { push @$list, @$r }
    return $list;
  }
}

sub smembers {
  my $cur = shift->_clone('SSCAN', shift);
  return $cur->slurp(@_);
}

sub _clone {
  my $self = shift;
  return $self->new(@_)->redis($self->redis);
}

1;

=encoding utf8

=head1 NAME

Mojo::Redis2::Cursor - Cursor iterator for SCAN commands.

=head1 SYNOPSIS

  use Mojo::Redis2;
  use Mojo::Redis2::Cursor;

  my $redis = Mojo::Redis2->new();
  my $cursor
    = Mojo::Redis2::Cursor->new('SCAN', match => 'mynamespace*')->redis($redis);

  # blocking
  while (my $r = $cursor->next) { say join "\n", @$r }

  # or non-blocking
  use feature 'current_sub';
  $cursor->next(
    sub {
      my ($cur, $err, $r) = @_;
      say join "\n", @$r;
      return Mojo::IOLoop->stop() unless $cur->next(__SUB__);
    }
  );
  Mojo::IOLoop->start();


=head1 DESCRIPTION

L<Mojo::Redis2::Cursor> is an iterator object for C<SCAN> family commands.

=head1 ATTRIBUTES

=head2 command

 my $command = $cursor->command;

Command to be issued to server.

=head2 key

  my $key    = $cursor->key;
  my $cursor = $cursor->key('new.redis.key');

Redis key to work with for commands that need it. Overrides value from L</new>.

=head1 METHODS

L<Mojo::Redis2::Cursor> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 again

  $cursor->again();
  my $res = $cursor->again->slurp();

Reset cursor to start iterating from the beginning.

=head2 finished

  my $is_finished = $cursor->finished();

Indicate that full iteration had been made and no additional elements can be
fetched.

=head2 hgetall

  my $hash = $redis2->scan->hgetall('redis.key');
  $hash = $cursor->hgetall('redis.key');
  $cursor->hgetall('redis.key' => sub {...});

Implements standard C<HGETALL> command using C<HSCAN>.

=head2 hkeys

  my $keys = $redis2->scan->hkeys('redis.key');
  $keys = $cursor->hkeys('redis.key');
  $cursor->hkeys('redis.key' => sub {...});

Implements standard C<HKEYS> command using C<HSCAN>.

=head2 keys

  my $keys = $redis2->scan->keys;
  $keys = $cursor->keys('*');
  $cursor->keys('*' => sub {
    my ($cur, $err, $keys) = @_;
    ...
  });

Implements standard C<KEYS> command using C<SCAN>.

=head2 new

  my $cursor  = Mojo::Redis2::Cursor->new(SCAN => MATCH => 'namespace*');
  my $zcursor = Mojo::Redis2::Cursor->new(ZSCAN => 'redis.key', COUNT => 15);

Object constructor. Follows same semantics as Redis command, except you B<should>
omit cursor field.

=head2 next

  # blocking
  my $res = $cursor->next();

  # non-blocking
  $cursor->next(sub {
    my ($cur, $err, $res) = @_;
    ...
  })

Issue next C<SCAN> family command with cursor value from previous iteration. If
last argument is coderef, will made a non-blocking call. In blocking mode returns
arrayref with fetched elements. If no more items available, will return
C<undef>, for both blocking and non-blocking, without calling callback.

  my $res = $cursor->next(MATCH => 'namespace*');
  $cursor->next(COUNT => 100, sub { ... });

Accepts the same optional arguments as original Redis command, which will replace
old values and will be used for this and next iterations.

=head2 slurp

  my $keys = $cursor->slurp(COUNT => 5);
  $cursor->slurp(sub {
    my ($cur, $err, $res) = @_;
  });

Repeatedly call L</next> to fetch all matching elements. Optional
arguments will be passed along.

In case of error will return all data fetched so far.

=head2 smembers

  my $list = $redis2->scan->smembers('redis.key');
  $list = $cursor->smembers('redis.key');
  $cursor->smembers('redis.key' => sub {...});

Implements standard C<SMEMBERS> command using C<SSCAN>.

=head1 LINKS

L<http://redis.io/commands>

=cut
