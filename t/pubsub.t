use Mojo::Base -strict;
use Test::More;
use Mojo::Redis;

plan skip_all => 'TEST_ONLINE=redis://localhost' unless $ENV{TEST_ONLINE};
*memory_cycle_ok = eval 'require Test::Memory::Cycle;1' ? \&Test::Memory::Cycle::memory_cycle_ok : sub { };

my $redis = Mojo::Redis->new($ENV{TEST_ONLINE});
my $db    = $redis->db;
memory_cycle_ok($redis, 'cycle ok for Mojo::Redis');

my $pubsub = $redis->pubsub;
my (@messages, @res);
memory_cycle_ok($redis, 'cycle ok for Mojo::Redis::PubSub');

is ref($pubsub->listen(rtest1 => \&gather)), 'CODE', 'listen';
$pubsub->listen(rtest2 => \&gather);
diag 'Waiting for subscriptions to be set up...';
Mojo::IOLoop->timer(0.15 => sub { Mojo::IOLoop->stop });
Mojo::IOLoop->start;
memory_cycle_ok($redis, 'cycle ok after listen');

$pubsub->notify(rtest1 => 'message one');
$db->publish_p(rtest2 => 'message two');
memory_cycle_ok($redis, 'cycle ok after notify');

Mojo::IOLoop->start;
is_deeply [sort @messages], ['message one', 'message two'], 'got messages' or diag join ", ", @messages;

is $pubsub->unlisten('rtest1'), $pubsub, 'unlisten';
memory_cycle_ok($pubsub, 'cycle ok after unlisten');
$db->publish_p(rtest1 => 'nobody is listening to this');

diag 'Making sure the last message is not received';
Mojo::IOLoop->timer(0.15 => sub { Mojo::IOLoop->stop });
Mojo::IOLoop->start;
is_deeply [sort @messages], ['message one', 'message two'], 'got messages' or diag join ", ", @messages;

my $conn = $pubsub->connection;
is @{$conn->subscribers('message')}, 1, 'only one message subscriber';

undef $pubsub;
undef $redis->{pubsub};
isnt $redis->db->connection, $conn, 'pubsub connection cannot be re-used';

done_testing;

sub gather {
  push @messages, $_[1];
  Mojo::IOLoop->stop if @messages == 2;
}
