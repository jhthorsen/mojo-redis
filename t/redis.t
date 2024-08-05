use Mojo::Base -strict;
use Test::More;
use Mojo::Redis;
use Mojo::URL;

my $redis = Mojo::Redis->new;
like $redis->protocol_class, qr{^Protocol::Redis},     'connection_class';
is $redis->max_connections,  5,                        'max_connections';
is $redis->url,              'redis://localhost:6379', 'default url';

$redis = Mojo::Redis->new('redis://redis.localhost', max_connections => 1);
is $redis->url, 'redis://redis.localhost', 'custom url';
is $redis->max_connections, 1, 'custom max_connections';
ok !defined $redis->tls, 'tls disabled by default';
ok !defined $redis->tls_ca, 'no tls ca certificate set by default';
ok !defined $redis->tls_cert, 'no custom client tls certificate set by default';
ok !defined $redis->tls_key, 'no custom client tls key set by default';
ok !defined $redis->tls_options, 'no custom tls options set by default';

$redis = Mojo::Redis->new(
    'redis://redis.localhost',
    tls         => 1,
    tls_ca      => '/var/mojo/app/ca.crt',
    tls_cert    => '/var/mojo/app/client.crt',
    tls_key     => '/var/mojo/app/client.key',
    tls_options => {SSL_alpn_protocols => ['foo']}
);
is $redis->url, 'redis://redis.localhost', 'custom url string';
is $redis->tls, 1, 'tls enabled';
is $redis->tls_ca, '/var/mojo/app/ca.crt', 'custom tls ca certificate';
is $redis->tls_cert, '/var/mojo/app/client.crt', 'custom client tls certificate';
is $redis->tls_key, '/var/mojo/app/client.key', 'custom client tls key';
is $redis->tls_options->{SSL_alpn_protocols}[0], 'foo', 'custom tls options';

$redis = Mojo::Redis->new(Mojo::URL->new('redis://redis.example.com')->userinfo('x:foo'));
is $redis->url, 'redis://redis.example.com', 'custom url object';
is $redis->url->userinfo, 'x:foo', 'userinfo retained';

$redis = Mojo::Redis->new({max_connections => 3});
is $redis->max_connections, 3, 'constructor with hash ref';

$redis = Mojo::Redis->new(max_connections => 2);
is $redis->max_connections, 2, 'constructor with list';

$ENV{MOJO_REDIS_URL} = 'redis://redis.env.localhost';
$redis = Mojo::Redis->new;
is $redis->url, 'redis://redis.env.localhost', 'custom default url';

done_testing;
