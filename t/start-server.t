use Mojo::Base -base;
use Test::More;
use Mojo::Redis2;

my $config;

{
  local $ENV{REDIS_SERVER_BIN} = './does-not-exist-nope-for-sure-i-hope-not';
  $config = eval { Mojo::Redis2->start_server };
  like $@, qr{Could not start Redis}, 'No such file';
}

{
  $config = eval { Mojo::Redis2->start_server({ port => 123 }) };
  like $@, qr{Redis server failed to start|Could not start Redis}, 'Redis server failed to start';
}

SKIP: {
  $config = eval { Mojo::Redis2->start_server };
  skip 'redis-server is not installed', 2 if $@;
  like $config->{port}, qr{\d+}, 'port was generated';
  is $ENV{MOJO_REDIS_URL}, "redis://x:\@$config->{bind}:$config->{port}/", 'MOJO_REDIS_URL was generated';
  ok -r $config->{config_file}, 'config file exists';
  ok kill(0, $config->{pid}), 'server is running';

  {
    local $TODO = 'Should this be a public method?';
    is(Mojo::Redis2->_stop_server, 'Mojo::Redis2', '_stop_server() returns classname');
  }

  is waitpid($config->{pid}, 0), $config->{pid}, 'wait()ed for server to stop';
  ok !kill(0, $config->{pid}), 'server was stopped';
  ok !-r $config->{config_file}, 'config file was cleaned up';
}

done_testing;
