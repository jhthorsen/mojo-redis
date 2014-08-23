use Mojo::Base -strict;
use Test::More;
use Mojo::Redis2::Server;
my $pid;

{
  my $server = Mojo::Redis2::Server->new;
  local $ENV{REDIS_SERVER_BIN} = './does-not-exist-nope-for-sure-i-hope-not';
  eval { $server->start };
  like $@, qr{Failed to start}, 'No such file';
}

SKIP: {
  my $server = eval { Mojo::Redis2::Server->start };
  skip "redis-server is not installed: $@", 1 if $@;
  like $server->config->{port}, qr{\d+}, 'port was generated';
  is $ENV{MOJO_REDIS_URL}, "redis://x:\@$server->{config}{bind}:$server->{config}{port}/", 'MOJO_REDIS_URL was generated';
  ok kill(0, $server->pid), 'server is running';

  is(Mojo::Redis2::Server->stop, Mojo::Redis2::Server->singleton, 'stop');
  ok !kill(0, $server->pid), 'server was stopped';
}

SKIP: {
  my $server = Mojo::Redis2::Server->new;
  eval { $server->start };
  skip "redis-server is not installed: $@", 1 if $@;
  $pid = $server->pid;
}

if ($pid) {
  ok !kill(0, $pid), 'server was stopped on DESTROY';
}

done_testing;
