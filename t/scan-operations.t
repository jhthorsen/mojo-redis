use Mojo::Base -strict;
use Mojo::Redis2;
use Test::More;

plan skip_all => 'Cannot test on Win32' if $^O =~ /win/i;
plan skip_all => $@ unless eval { Mojo::Redis2::Server->start };

use constant ELEMENTS_COUNT => $ENV{REDIS2_TEST_ELEMENTS_COUNT} || 5_000;

my $redis = Mojo::Redis2->new();

# constructor
my $cursor = $redis->scan(MATCH => '*', COUNT => 100);
is $cursor->_command->[0], 'SCAN', 'right command SCAN';
is_deeply $cursor->_args, ['MATCH', '*', 'COUNT', 100], 'right args';
$cursor = $redis->hscan('redis2.scan_test.key', COUNT => 20);
is $cursor->_command->[0], 'HSCAN', 'right command HSCAN';
is $cursor->_command->[1], 'redis2.scan_test.key', 'right key';
is_deeply $cursor->_args, ['COUNT', 20], 'right args';
$cursor = $redis->sscan('redis2.scan_test.key');
is $cursor->_command->[0], 'SSCAN', 'right command SSCAN';
$cursor = $redis->zscan('redis2.scan_test.key');
is $cursor->_command->[0], 'ZSCAN', 'right command ZSCAN';

$redis->set("redis2.scan_test.key.$_", $_) for 1 .. ELEMENTS_COUNT;
my $list = [];
my $expected = [sort map {"redis2.scan_test.key.$_"} 1 .. ELEMENTS_COUNT];

# blocking
$cursor = $redis->scan(MATCH => 'redis2.scan_test.key.*');

# next
my $guard = 1000;
while ($guard-- && (my $r = $cursor->next())) { push @$list, @$r }
is_deeply [sort @$list], $expected, 'fetch with next blocking';

# again
ok $cursor->finished, 'finished is set';
$cursor->again();
is $cursor->_cursor, 0, 'reset cursor';
ok !$cursor->finished, 'reset finished';

# slurp
$list = [];
$list = $cursor->all();
is_deeply [sort @$list], $expected, 'fetch all blocking';

# non-blocking
$list  = [];
$guard = 1000;
my $cb;
$cb = sub {
  my ($cur, $err, $res) = @_;
  push @$list, @{$res // []};
  return Mojo::IOLoop->stop() unless $guard-- && $cur->next($cb);
};
$cursor->again->next($cb);
Mojo::IOLoop->start();
is_deeply [sort @$list], $expected, 'fetch with next non-blocking';
$list = [];
$cursor->again->all(sub { $list = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply [sort @$list], $expected, 'fetch all non-blocking';

# hscan
$redis->hset('redis2.scan_test.hash', "key.$_" => "val.$_")
  for 1 .. ELEMENTS_COUNT;
$expected = {map { 'key.' . $_ => 'val.' . $_ } (1 .. ELEMENTS_COUNT)};
$cursor   = $redis->hscan('redis2.scan_test.hash');
$list     = $cursor->all();
is_deeply {@$list}, $expected, 'right result hscan';

# hscan nb
$list = [];
$cursor->again->all(sub { $list = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply {@$list}, $expected, 'right result hscan non-blocking';

# sscan
$redis->sadd('redis2.scan_test.set', $_) for 1 .. ELEMENTS_COUNT;
$expected = [sort 1 .. ELEMENTS_COUNT];
$cursor   = $redis->sscan('redis2.scan_test.set');
$list     = $cursor->all();
is_deeply [sort @$list], $expected, 'right result sscan';

# sscan nb
$list = [];
$cursor->again->all(sub { $list = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply [sort @$list], $expected, 'right result sscan non-blocking';

# zscan
$redis->zadd('redis2.scan_test.zset', $_, "val.$_") for 1 .. ELEMENTS_COUNT;
$expected = sort_zset([map { 'val.' . $_ => $_ } 1 .. ELEMENTS_COUNT]);
$cursor   = $redis->zscan('redis2.scan_test.zset');
$list     = $cursor->all();
is_deeply sort_zset($list), $expected, 'right result zscan';

# zscan nb
$list = [];
$cursor->again->all(sub { $list = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply sort_zset($list), $expected, 'right result zscan non-blocking';

# errors
eval { $cursor = $redis->scan(0, MATCH => '*') };
ok $@ && $@ =~ /ERR Should not specify cursor value/,
  'right error manual cursor';
$cursor = $redis->scan(FOO => 'bar');
eval { $list = $cursor->all() };
ok $@ && $@ =~ /ERR syntax error/, 'right error redis syntax';
my $error;
$cursor->again->all(sub { $error = $_[1]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
ok $error && $error =~ /ERR syntax error/, 'right error redis syntax nb';

# helpers
my $keys = $redis->keys('redis2.scan_test.key.*');
@$keys = sort @$keys;
my $keysh = $cursor->keys('redis2.scan_test.key.*');
is_deeply [sort @$keysh], $keys, 'same results for keys';
$keysh = [];
$cursor->keys(
  'redis2.scan_test.key.*' => sub { $keysh = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply [sort @$keysh], $keys, 'same results for keys nb';

$keys  = $redis->hkeys('redis2.scan_test.hash');
@$keys = sort @$keys;
$keysh = $cursor->hkeys('redis2.scan_test.hash');
is_deeply [sort @$keysh], $keys, 'same results for hkeys';
$keysh = [];
$cursor->hkeys(
  'redis2.scan_test.hash' => sub { $keysh = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply [sort @$keysh], $keys, 'same results for hkeys nb';

$keys  = $redis->hgetall('redis2.scan_test.hash');
$keysh = $cursor->hgetall('redis2.scan_test.hash');
is_deeply {@$keysh}, {@$keys}, 'same results for hgetall';
$keysh = [];
$cursor->hgetall(
  'redis2.scan_test.hash' => sub { $keysh = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply {@$keysh}, {@$keys}, 'same results for hgetall nb';

$keys  = $redis->smembers('redis2.scan_test.set');
@$keys = sort @$keys;
$keysh = $cursor->smembers('redis2.scan_test.set');
is_deeply [sort @$keysh], $keys, 'same results for smembers';
$keysh = [];
$cursor->smembers(
  'redis2.scan_test.set' => sub { $keysh = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply [sort @$keysh], $keys, 'same results for smembers nb';


done_testing;

sub sort_zset {
  my %set = @{$_[0]};
  return [map { $_ => $set{$_} } sort keys %set];
}
