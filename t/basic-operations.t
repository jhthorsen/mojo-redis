use Mojo::Base -base;
use Mojo::Redis2;
use Test::More;

plan skip_all => $@ unless eval { Mojo::Redis2->start_server };

my $redis = Mojo::Redis2->new;
my ($ping_err, $ping, $get_err, $get);

is $redis->set('mojo:redis2:scalar' => 42), 'OK', 'SET mojo:redis2:test:get 42';
is $redis->get('mojo:redis2:scalar'), 42, 'GET mojo:redis2:test:get';

Mojo::IOLoop->delay(
  sub {
    my ($delay) = @_;
    $redis->ping($delay->begin)->get("mojo:redis2:scalar", $delay->begin);
  },
  sub {
    (my $delay, $ping_err, $ping, $get_err, $get) = @_;
    Mojo::IOLoop->stop;
  },
);
Mojo::IOLoop->start;

is $ping_err, '', 'no ping error';
is $ping, 'PONG', 'got PONG';
is $get_err, '', 'no get error';
is $get, 42, 'got 42';

is_deeply $redis->del('mojo:redis2:scalar'), '1', 'DEL mojo:redis2:test:get';

done_testing;
