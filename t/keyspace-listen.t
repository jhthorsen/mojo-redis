use Mojo::Base -strict;
use Test::More;
use Mojo::Redis;

my @messages;
my $redis  = Mojo::Redis->new('redis://localhost');
my $pubsub = $redis->pubsub;
is $pubsub->_keyspace_key, '__keyevent@*__:*', 'keyevent default db wildcard';

$redis->url->path->parse('/5');
is $pubsub->_keyspace_key, '__keyevent@5__:*', 'keyevent default wildcard';
is $pubsub->_keyspace_key({type => 'key*'}), '__key*@5__:*', 'keyboth wildcard listen';
is $pubsub->_keyspace_key(foo => undef), '__keyspace@5__:foo', 'keyspace foo';
is $pubsub->_keyspace_key(undef, 'del'), '__keyevent@5__:del', 'keyevent del';
is $pubsub->_keyspace_key('foo', 'rename', {db => 1, key => 'x', op => 'y'}), '__keyspace@1__:foo',
  'keyspace foo and db';
is $pubsub->_keyspace_key({db => 0, key => 'foo', type => 'key*'}), '__key*@0__:foo', 'key* db and type';

my $cb = $pubsub->keyspace_listen(undef, 'del', {db => 1}, sub { });
is ref($cb), 'CODE', 'keyspace_listen returns callback';
is_deeply $pubsub->{chans}{'__keyevent@1__:del'}, [$cb], 'callback is set up';
is $pubsub->keyspace_unlisten(undef, 'del', {db => 1}, $cb), $pubsub, 'keyspace_unlisten with callback';
ok !$pubsub->{chans}{'__keyevent@1__:del'}, 'callback is removed';
$pubsub->{chans}{'__keyevent@1__:del'} = [$cb];
is $pubsub->keyspace_unlisten(undef, 'del', {db => 1}), $pubsub, 'keyspace_unlisten without callback';
ok !$pubsub->{chans}{'__keyevent@1__:del'}, 'callback is removed';

done_testing;
