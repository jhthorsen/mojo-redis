use Mojo::Base -strict;
use Mojo::Redis2;
use Test::More;

my $port = Mojo::IOLoop::Server->generate_port;
my $redis = Mojo::Redis2->new(url => "redis://127.0.42.123:$port");
my ($err, $res);

Mojo::IOLoop->delay(
  sub {
    my ($delay) = @_;
    $redis->get(foo => $delay->begin);
  },
  sub {
    (my $delay, $err, $res) = @_;
    Mojo::IOLoop->stop;
  },
);
Mojo::IOLoop->start;

is eval { $redis->get('foo'); 1 }, undef, 'get failed';
my $e = $@;
is $res, undef,           'get foo';
like $e, qr{\[GET foo\]}, 'connection failed';
like $e, qr{$err},        "sync contains async error ($err)";

done_testing;
