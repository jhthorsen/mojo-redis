use Mojo::Base -strict;
use Mojo::Redis2;
use Test::More;

my $redis = Mojo::Redis2->new(url => 'localhost:1234567');

is eval { $redis->get('foo'); 1 }, undef, 'get failed';
like $@, qr{\[GET foo\]}, 'connection failed';

done_testing;
