use Mojo::Base -strict;
use Mojo::Redis2;
use Test::More;

plan skip_all => $@ unless eval { Mojo::Redis2->start_server };

my $redis = Mojo::Redis2->new;
my $bulk = $redis->bulk;
my ($err, $res);

$res = eval { $bulk->ping->set(foo => 123)->get("foo")->execute };
is_deeply $res, [ 'PONG', 'OK', '123', ], 'got sync res';

Mojo::IOLoop->delay(
  sub {
    my ($delay) = @_;
    $bulk->ping->set(foo => 123)->get("foo")->execute($delay->begin);
  },
  sub {
    (my $delay, $err, $res) = @_;
    Mojo::IOLoop->stop;
  },
);
Mojo::IOLoop->start;

is $err->compact->join('. '), '', 'no errors';
is_deeply $res, [ 'PONG', 'OK', '123', ], 'got async res';

done_testing;
