package Mojo::Redis::Transaction;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::Redis::Database;

has connection => sub { shift->redis->_dequeue };
has redis      => sub { Carp::confess('redis is required in constructor') };

our @TXN_COMMANDS = ('discard', 'multi', 'unwatch', 'watch');

Mojo::Redis::Database->_add_bnp_method($_) for @TXN_COMMANDS;

sub exec {
  my ($self, $cb) = @_;
  $self->{done} = 1;
}

sub DESTROY {
  my $self = shift;
  return unless (my $redis = $self->redis) && (my $conn = $self->connection);
  $conn->write_p('DISCARD') unless $self->{done};
  $redis->_enqueue($conn);
}

1;
