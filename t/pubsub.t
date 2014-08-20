use Mojo::Base -strict;
use Mojo::Redis2;
use Test::More;

plan skip_all => $@ unless eval { Mojo::Redis2->start_server };

my $redis = Mojo::Redis2->new;
my $p = 1;
my (@err, @res, @messages, @redis);

{
  my $subscribe_cb = sub {
    push @res, pop;
    push @err, pop;
    $p += $redis->publish("mojo:redis:test" => "message $p");
    diag "sub+pub: $p";
  };
  my $psubscribe_cb = sub {
    push @res, pop;
    push @err, pop;
    $p += $redis->publish("mojo:redis:test" => "message $p");
    diag "psub+pub: $p";
    $p += $redis->publish("mojo:redis:channel2" => "message $p");
    diag "psub+pub: $p";
  };

  $redis->on(message => sub {
    shift;
    push @messages, [message => @_];
    push @redis, $redis->psubscribe("mojo:redis:ch*", $psubscribe_cb) if @messages == 1;
    Mojo::IOLoop->stop if @messages == 3;
  });
  $redis->on(pmessage => sub {
    shift;
    push @messages, [pmessage => @_];
    Mojo::IOLoop->stop if @messages == 3;
  });

  is $redis->subscribe("mojo:redis:test", $subscribe_cb), $redis, 'subscribe()';
  Mojo::IOLoop->start;

  is_deeply \@redis, [$redis], 'psubscribe()';
  is_deeply \@err, ['', ''], 'no subscribe error';
  is_deeply(
    \@res,
    [
      [qw( subscribe mojo:redis:test 1 )],
      [qw( psubscribe mojo:redis:ch* 2 )],
    ],
    'subscribed to one channel'
  );

  is_deeply(
    \@messages,
    [
      [ message => "message 1", "mojo:redis:test" ],
      [ message => "message 2", "mojo:redis:test" ],
      [ pmessage => "message 3", "mojo:redis:channel2", "mojo:redis:ch*" ],
    ],
    'got message events',
  );

  is $p, 4, 'published messages';
}

done_testing;
