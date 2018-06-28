use Mojo::Base -strict;
use Test::More;
use Mojo::Redis;

plan skip_all => 'TEST_ONLINE=redis://localhost' unless $ENV{TEST_ONLINE};

my $redis = Mojo::Redis->new($ENV{TEST_ONLINE});
my $cache = $redis->cache(namespace => $0);
my $n     = 0;
my $res;

cleanup();

for (1 .. 2) {
  $cache->compute_p(
    'some:key',
    60.7,
    sub {
      $n++;
      my $p = Mojo::Promise->new;
      Mojo::IOLoop->timer(0.1 => sub { $p->resolve('some data') });
      return $p;
    }
  )->then(sub { $res = shift })->wait;

  is $res, 'some data', 'computed some:key';

  $cache->compute_p(
    'some:other:key',
    sub {
      $n++;
      return +{some => "data"};
    }
  )->then(sub { $res = shift })->wait;

  is_deeply $res, {some => 'data'}, 'computed some:other:key';
}

is $n, 2, 'compute only called twice';

$cache->compute_p('some:die:key', sub { die 'oops!' })->catch(sub { $res = shift })->then(sub { $res = shift })->wait;
like $res, qr{oops!}, 'failed to cache';

cleanup();
done_testing;

sub cleanup {
  $redis->db->del(map {"$0:$_"} 'some:key', 'some:die:key', 'some:other:key');
}
