BEGIN { $ENV{MOJO_REDIS_CACHE_OFFLINE} = 1 }
use Mojo::Base -strict;
use Test::More;
use Mojo::Redis;
*memory_cycle_ok = eval 'require Test::Memory::Cycle;1' ? \&Test::Memory::Cycle::memory_cycle_ok : sub { };

my $redis = Mojo::Redis->new;
my $cache = $redis->cache(namespace => $0);
my $n     = 0;
my $res;
memory_cycle_ok($redis, 'cycle ok for Mojo::Redis::Cache');

for (1 .. 2) {
  $cache->memoize_p(main => 'cache_me', [{foo => 42}])->then(sub { $res = shift })->wait;
  is_deeply $res, {foo => 42}, 'memoize cache_me with hash';
}
memory_cycle_ok($cache, 'cycle ok after memoize_p');

is $n, 1, 'compute only called once per key';

$cache->refresh(1)->memoize_p(main => 'cache_me', [{foo => 42}])->then(sub { $res = shift })->wait;
is $n, 2, 'compute called after refresh()';
memory_cycle_ok($cache, 'cycle ok after refresh');

$cache->compute_p('some:die:key', sub { die 'oops!' })->catch(sub { $res = shift })->then(sub { $res = shift })->wait;
like $res, qr{oops!}, 'failed to cache';
memory_cycle_ok($cache, 'cycle ok after compute_p');

{
  no warnings 'redefine';
  local *Mojo::Redis::Cache::_time = sub { time + 601 };
  $cache->refresh(0)->memoize_p(main => 'cache_me', [{foo => 42}])->then(sub { $res = shift })->wait;
  is $n, 3, 'compute called after expired';
}
memory_cycle_ok($cache, 'cycle ok after memoize_p expired');

done_testing;

sub cache_me {
  $n++;
  return $_[1] || 'default value';
}
