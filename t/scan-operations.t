use Mojo::Base -strict;
use Mojo::Redis2;
use Test::More;

plan skip_all => 'Cannot test on Win32' if $^O =~ /win/i;
plan skip_all => $@ unless eval { Mojo::Redis2::Server->start };

my $redis = Mojo::Redis2->new();

# constructor
my $cursor = $redis->scan(MATCH => '*', COUNT => 100);
is $cursor->command, 'SCAN', 'right command SCAN';
is_deeply $cursor->_args, ['MATCH', '*', 'COUNT', 100], 'right args';
$cursor = $redis->hscan('redis2.scan_test.key', COUNT => 20);
is $cursor->command, 'HSCAN', 'right command HSCAN';
is $cursor->key, 'redis2.scan_test.key', 'right key';
is_deeply $cursor->_args, ['COUNT', 20], 'right args';
$cursor = $redis->sscan('redis2.scan_test.key');
is $cursor->command, 'SSCAN', 'right command SSCAN';
$cursor = $redis->zscan('redis2.scan_test.key');
is $cursor->command, 'ZSCAN', 'right command ZSCAN';

$redis->set("redis2.scan_test.key.$_", $_) for 1 .. 20;
my $list = [];
my $expected = [sort map {"redis2.scan_test.key.$_"} 1 .. 20];

# blocking
$cursor = $redis->scan(MATCH => 'redis2.scan_test.key.*');

# next
my $guard = 100;
while ($guard-- && (my $r = $cursor->next())) { push @$list, @$r }
is_deeply [sort @$list], $expected, 'fetch with next blocking';

# again
ok $cursor->finished, 'finished is set';
$cursor->again();
is $cursor->_cursor, 0, 'reset cursor';
ok !$cursor->finished, 'reset finished';

# slurp
$list = [];
$list = $cursor->slurp();
is_deeply [sort @$list], $expected, 'slurp blocking';

# non-blocking
$list = [];
$guard = 100;
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
$cursor->again->slurp(sub { $list = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply [sort @$list], $expected, 'slurp non-blocking';

# hscan
$redis->hset('redis2.scan_test.hash', "key.$_" => "val.$_") for 1 .. 10;
$expected = {map { 'key.' . $_ => 'val.' . $_ } (1 .. 10)};
$cursor   = $redis->hscan('redis2.scan_test.hash');
$list     = $cursor->slurp();
is_deeply {@$list}, $expected, 'right result hscan';

# hscan nb
$list = [];
$cursor->again->slurp(sub { $list = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply {@$list}, $expected, 'right result hscan non-blocking';

# sscan
$redis->sadd('redis2.scan_test.set', $_) for 1 .. 10;
$expected = [sort 1 .. 10];
$cursor   = $redis->sscan('redis2.scan_test.set');
$list     = $cursor->slurp();
is_deeply [sort @$list], $expected, 'right result sscan';

# sscan nb
$list = [];
$cursor->again->slurp(sub { $list = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply [sort @$list], $expected, 'right result sscan non-blocking';

# zscan
$redis->zadd('redis2.scan_test.zset', $_, "val.$_") for 1 .. 10;
$expected = sort_zset([map { 'val.' . $_ => $_ } 1 .. 10]);
$cursor   = $redis->zscan('redis2.scan_test.zset');
$list     = $cursor->slurp();
is_deeply sort_zset($list), $expected, 'right result zscan';

# zscan nb
$list = [];
$cursor->again->slurp(sub { $list = $_[2]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is_deeply sort_zset($list), $expected, 'right result zscan non-blocking';

# errors
eval { $cursor = $redis->scan(0, MATCH => '*') };
ok $@ && $@ =~ /ERR Should not specify cursor value/,
  'right error manual cursor';
$cursor = $redis->scan(FOO => 'bar');
eval { $list = $cursor->slurp() };
ok $@ && $@ =~ /ERR syntax error/, 'right error redis syntax';
my $error;
$cursor->again->slurp(sub { $error = $_[1]; Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
ok $error && $error =~ /ERR syntax error/, 'right error redis syntax nb';

done_testing;

sub sort_zset {
  my %set = @{$_[0]};
  return [map { $_ => $set{$_} } sort keys %set];
}
