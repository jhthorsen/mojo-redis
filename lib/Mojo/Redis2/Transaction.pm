package Mojo::Redis2::Transaction;

=head1 NAME

Mojo::Redis2::Transaction - Transaction guard for Mojo::Redis2

=head1 DESCRIPTION

L<Mojo::Redis2::Transaction> is an object for handling transactions started
by L<Mojo::Redis2/multi>.

All transactions objects will be kept isolated having its own connection to
the database. One object can also be re-used: Calling a
L<Redis method|Mojo::Redis2/METHODS> after L</exec> or L</discard> will
result in sending the "MULTI" command to the Redis server again.

L</discard> is automatically called when an instance of
L<Mojo::Redis2::Transaction> goes out of scope.

=head1 SYNOPSIS

  use Mojo::Redis2;
  my $redis = Mojo::Redis2->new;

  my $txn = $redis->multi;
  $txn->set(foo => 42);
  $txn->exec;

  # the same object (and connection to database) can be re-used
  $txn->incr('foo');
  $txn->discard;

=cut

use Mojo::Base 'Mojo::Redis2';

our $VERSION = '0.01';

=head1 ATTRIBUTES

L<Mojo::Redis2::Transaction> inherits all attributes from L<Mojo::Redis2>.

=head1 METHODS

L<Mojo::Redis2::Transaction> inherits all methods from L<Mojo::Redis2> and
implements the following new ones.

=head2 exec

  $self->exec;
  $self->exec(sub { my ($self, $err, $res) = @_; });

Execute all commands issued.

=cut

sub exec {
  my $self = shift;
  $self->{exec} = 1;
  $self->_execute_if_instructions(EXEC => @_);
}

=head2 discard

  $self->discard;
  $self->discard(sub { my ($self, $err, $res) = @_; });

Discard all commands issued. This method is called automatically on DESTROY,
unless L</exec> was called first.

=cut

sub discard {
  shift->_execute_if_instructions(DISCARD => @_);
}

sub DESTROY {
  my $self = shift;
  $self->discard if $self->{instructions} and !$self->{exec};
}

sub _blocking_group { 'txn' }

sub _execute {
  my ($self, $group, $op) = (shift, shift, shift);

  if (!grep { $op eq $_ } qw( EXEC DISCARD ) and !$self->{instructions}++) {
    $self->{exec} = 0;
    $self->{connections}{txn} ||= { group => 'txn', nb => ref $_[-1] eq 'CODE' ? 1 : 0 };
    push @{ $self->{connections}{txn}{queue} }, [ undef, 'MULTI' ];
  }

  $self->SUPER::_execute(txn => $op, @_);
}

sub _execute_if_instructions {
  my @cb = ref $_[-1] eq 'CODE' ? (pop) : ();
  my ($self, $action) = @_;
  my $res;

  if (delete $self->{instructions}) {
    $res = $self->_execute(txn => $action, @cb);
  }
  elsif (my $cb = $cb[0]) {
    $self->$cb($action eq 'EXEC' ? [] : 'OK');
  }
  else {
    return $action eq 'EXEC' ? [] : 'OK';
  }

  return $res;
}

=head1 ILLEGAL METHODS

The following methods cannot be called on an instance of
L<Mojo::Redis2::Transaction>.

=over 4

=item * multi

=item * psubscribe

=item * publish

=item * subscribe

=back

=cut

for my $illegal (qw( multi psubscribe publish subscribe )) {
  no strict 'refs';
  *$illegal = sub { die "Cannot call $illegal() on $_[0]"; };
}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
