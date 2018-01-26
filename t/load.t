use Mojo::Base -strict;
use Mojo::IOLoop;
use Mojo::Redis2;
use Mojo::URL;
use Test::More;

# Logic of the test is following:
# 1. client subscribes to channel
# 2. client publishes a message on channel
# 4. client recieves message on a channel
# All counters should be the same

use constant {TEST_MESSAGES => 500, TIMEOUT => 3};

plan skip_all => 'Cannot test on Win32' if $^O eq 'MSWin32';

# not sure if setting requirepass and path matter,
# but adding it for the sake of complexity
plan skip_all => $@ unless eval { Mojo::Redis2::Server->start(requirepass => 's3cret') };
my $url = Mojo::URL->new($ENV{MOJO_REDIS_URL})->path(3);
my $redis = Mojo::Redis2->new(url => $url);

my ($got_messages, $subscribed);

$redis->on(
  message => sub {
    my ($self, $msg, $channel) = @_;
    $got_messages++ if $msg eq $channel;
  }
);
for my $channel (1 .. TEST_MESSAGES) {
  $redis->subscribe(
    [$channel],
    sub {
      $subscribed++;
      my ($redis, $err) = @_;
      $redis->publish($channel, $channel);
    }
  );
}

# stop processing if all requests are finished
Mojo::IOLoop->timer(TIMEOUT() => sub { Mojo::IOLoop->stop });
Mojo::IOLoop->start;

is $subscribed, TEST_MESSAGES, 'all subscribtions were successfull';
is $got_messages, $subscribed, 'number of sent messages is equal to the number of received';

done_testing;
