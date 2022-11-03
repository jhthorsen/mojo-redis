use Mojo::Base -strict;
use Test::More;
use Mojo::JSON qw(encode_json);
use Mojo::Redis;

plan skip_all => 'TEST_ONLINE=redis://localhost' unless $ENV{TEST_ONLINE};
*memory_cycle_ok
  = eval 'require Test::Memory::Cycle;1' ? \&Test::Memory::Cycle::memory_cycle_ok : sub { ok 1, 'memory_cycle_ok' };

my $redis  = Mojo::Redis->new($ENV{TEST_ONLINE});
my $db     = $redis->db;
my $pubsub = $redis->pubsub;
my (@messages, @res);
my $events = {error => 0, psubscribe => 0, subscribe => 0};

subtest memory => sub {
  memory_cycle_ok($redis, 'cycle ok for Mojo::Redis');
  memory_cycle_ok($redis, 'cycle ok for Mojo::Redis::PubSub');
};

subtest events => sub {
  $pubsub->on(error      => sub { $events->{error}++ });
  $pubsub->on(psubscribe => sub { $events->{psubscribe}++ });
  $pubsub->on(subscribe  => sub { $events->{subscribe}++ });

  is ref($pubsub->listen("rtest:$$:1" => \&gather)), 'CODE', 'listen';
  $pubsub->listen("rtest:$$:2" => \&gather);
  note 'Waiting for subscriptions to be set up...';
  Mojo::Promise->timer(0.15)->wait;
  memory_cycle_ok($redis, 'cycle ok after listen');
};

subtest multi_listen => sub {
  is ref($pubsub->listen((map {"rtest:$$:M$_"} ("10" .. "30")), \&gather)), 'CODE', 'listen';
  $pubsub->listen((map {"rtest:$$:?$_"} ("10" .. "14")), \&gather);

  note 'Waiting for subscriptions to be set up...';
  Mojo::Promise->timer(0.15)->wait;
  memory_cycle_ok($redis, 'cycle ok after multi_listen');
};

subtest notify => sub {
  $pubsub->notify("rtest:$$:1"   => 'message one');
  $pubsub->notify("rtest:$$:M14" => 'message two');
  $db->publish_p("rtest:$$:2" => 'message three')->wait;

  memory_cycle_ok($redis, 'cycle ok after notify');

  wait_for_messages(4);

  has_messages(
    "rtest:$$:1/message one",
    "rtest:$$:M14/message two",
    "rtest:$$:M14/message two",
    "rtest:$$:2/message three"
  );
};

subtest channels => sub {
  $pubsub->channels_p("rtest:$$:?")->then(sub { @res = @_ })->wait;
  is_deeply [sort @{$res[0]}], ["rtest:$$:1", "rtest:$$:2"], 'channels_p:simple';

  $pubsub->channels_p("r????:$$:M[1-3][0-9]")->then(sub { @res = @_ })->wait;
  is_deeply [sort @{$res[0]}], [map {"rtest:$$:M$_"} ("10" .. "30")], 'channels_p:complex';
};

subtest numsub => sub {
  $pubsub->numsub_p("rtest:$$:1")->then(sub { @res = @_ })->wait;
  is_deeply $res[0], {"rtest:$$:1" => 1}, 'numsub_p';

  $pubsub->numsub_p("rtest:$$:M12", "rtest:$$:M30")->then(sub { @res = @_ })->wait;
  is_deeply $res[0], {"rtest:$$:M12" => 1, "rtest:$$:M30" => 1}, 'numsub_p';
};

# If tests are running in parallel then numpat_p will catch some other tests
# so the best we can do for this test is to ensure there are at least 5.
subtest numpat => sub {
  $pubsub->numpat_p->then(sub { @res = @_ })->wait;
  ok ($res[0] >= 5, 'numpat_p');
};

subtest unlisten => sub {
  is $pubsub->unlisten("rtest:$$:1"), $pubsub, 'unlisten';
  $pubsub->unlisten((map {"rtest:$$:M$_"} ("15" .. "25")));

  note 'Making sure the unlisten has completed';
  Mojo::Promise->timer(0.15)->wait;

  memory_cycle_ok($pubsub, 'cycle ok after unlisten');

  $pubsub->notify("rtest:$$:1" => 'nobody is listening to this');
  $db->publish_p("rtest:$$:M20" => 'nobody is listening to this either')->wait;

  note 'Making sure the last messages are not received';
  Mojo::Promise->timer(0.15)->wait;
  has_messages();
};

subtest 'listen patterns' => sub {
  $pubsub->listen("rtest:$$:[0-5]" => \&gather);
  $pubsub->listen("rtest:$$:[67]", "rtest:$$:??", '[^a]t[e]st:*:A?', \&gather);

  Mojo::Promise->timer(0.15)->wait;

  $pubsub->notify("rtest:$$:AA" => 'message eight');
  $pubsub->notify("rtest:$$:4"  => 'message four');
  $pubsub->notify("rtest:$$:5"  => 'message five');
  $pubsub->notify("rtest:$$:6"  => 'message six');
  $pubsub->notify("rtest:$$:7"  => 'message seven');

  wait_for_messages(6);

  has_messages(
    "rtest:$$:AA/message eight",
    "rtest:$$:AA/message eight",
    "rtest:$$:4/message four",
    "rtest:$$:5/message five",
    "rtest:$$:6/message six",
    "rtest:$$:7/message seven",
  );

  $pubsub->unlisten("rtest:$$:[4-5]", "rtest:$$:[67]", "rtest:$$:??", '[^a]t[e]st:*:A?');
  Mojo::Promise->timer(0.15)->wait;

};

subtest 'unlisten cbs' => sub {
  my $p_cb_pri = $pubsub->listen("rtest:$$:P*" => \&gather);
  my $p_cb_alt = $pubsub->listen("rtest:$$:P*", "rtest:$$:P*", \&gather_alt);

  my $m_cb_pri = $pubsub->listen("rtest:$$:10" => \&gather_alt);
  my $m_cb_alt = $pubsub->listen("rtest:$$:10", "rtest:$$:10", \&gather);

  my $ignore_pri = $pubsub->listen("rtest:$$:11" => \&gather);
  my $ignore_alt = $pubsub->listen("rtest:$$:11", "rtest:$$:11", \&gather_alt);

  note 'Making sure the listen has completed';
  Mojo::Promise->timer(0.15)->wait;

  note 'Removing same callback twice';
  $pubsub->unlisten("rtest:$$:P*", $p_cb_alt);
  $pubsub->unlisten("rtest:$$:P*", $p_cb_alt);

  note 'Removing two alternate callbacks';
  $pubsub->unlisten("rtest:$$:10", $m_cb_alt);

  note 'Removing entire channel w/o callbacks';
  $pubsub->unlisten("rtest:$$:11");

  $pubsub->notify("rtest:$$:P01" => 'pmessage one');
  $pubsub->notify("rtest:$$:10"  => 'message ten');
  $pubsub->notify("rtest:$$:11"  => 'message eleven');

  note 'Making sure the messages are received';
  Mojo::Promise->timer(0.15)->wait;

  memory_cycle_ok($pubsub, 'cycle ok after listen/unlisten');

  has_messages("rtest:$$:P01/pmessage one", "rtest:$$:10|message ten",);
};

subtest connection => sub {
  my $conn = $pubsub->connection;
  is @{$conn->subscribers('response')}, 1, 'only one message subscriber';

  undef $pubsub;
  delete $redis->{pubsub};
  isnt $redis->db->connection, $conn, 'pubsub connection cannot be re-used';
};

subtest 'json data' => sub {
  $pubsub = $redis->pubsub;
  $pubsub->listen("rtest:$$:1" => \&gather);
  Mojo::Promise->timer(0.15)->wait;

  $pubsub->notify_p("rtest:$$:1" => '{"invalid"');
  $pubsub->json("rtest:$$:1");
  $pubsub->notify("rtest:$$:1" => {some => 'data'});
  $pubsub->notify("rtest:$$:1" => 'just a string');
  wait_for_messages(3);

  has_messages("rtest:$$:1/undef", qq(rtest:$$:1/HASH/{"some":"data"}), "rtest:$$:1/just a string");
};

subtest events => sub {
  is_deeply $events, {error => 0, psubscribe => 10, subscribe => 25}, 'events';
};

done_testing;

sub gather {
  shift;
  push @messages, join '/', map { !defined($_) ? 'undef' : ref($_) ? (ref($_), encode_json($_)) : $_ } reverse @_;
}

sub gather_alt {
  shift;
  push @messages, join '|', map { !defined($_) ? 'undef' : ref($_) ? (ref($_), encode_json($_)) : $_ } reverse @_;
}

sub has_messages {
  is_deeply [sort @messages], [sort @_], 'has messages' or diag explain \@messages;
  @messages = ();
}

sub wait_for_messages {
  my $n = shift;
  Mojo::IOLoop->one_tick until @messages >= $n;
}
