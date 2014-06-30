use Mojo::Base -base;
use Test::More;
use Mojo::Redis2;

my $config;

{
  local $ENV{REDIS_SERVER_BIN} = './does-not-exist-nope-for-sure-i-hope-not';
  $config = eval { Mojo::Redis2->start_server };
  like $@, qr{No such file}, 'No such file';
}

{
  $config = eval { Mojo::Redis2->start_server({ port => 123 }) };
  like $@, qr{Redis server failed to start}, 'Redis server failed to start';
}

SKIP: {
  $config = eval { Mojo::Redis2->start_server };
  skip 'redis-server is not installed', 2 if $@;
  like $config->{port}, qr{\d+}, 'port was generated';
  is $ENV{MOJO_REDIS_URL}, "redis://x:\@$config->{bind}:$config->{port}/", 'MOJO_REDIS_URL was generated';
}

done_testing;
