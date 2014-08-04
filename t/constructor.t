use Mojo::Base -base;
use Mojo::Redis2;
use Test::More;

{
  my $redis = Mojo::Redis2->new;
  is $redis->url, 'redis://localhost:6379', 'url() is set';
  isa_ok $redis->protocol, $ENV{MOJO_REDIS_PROTOCOL};
}

{
  local $ENV{MOJO_REDIS_URL} = 'redis://x:z@localhost:42/3';
  my $redis = Mojo::Redis2->new;
  is $redis->url->host, 'localhost', 'url() host';
  is $redis->url->path->[0], '3', 'url() path';
  is $redis->url->port, '42', 'url() port';
  is $redis->url->userinfo, 'x:z', 'url() userinfo';
  is ref($redis->can('new')), 'CODE', 'new() is already there';
  is ref($redis->can('hgetall')), 'CODE', 'hgetall() added';
}

done_testing;
