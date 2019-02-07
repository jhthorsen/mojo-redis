use Mojo::Base -strict;
use Test::More;
use Mojo::Redis;

my $port   = Mojo::IOLoop::Server->generate_port;
my $conn_n = 0;
my @sent_to_server;

Mojo::IOLoop->server(
  {port => $port},
  sub {
    my ($loop, $stream) = @_;
    my $protocol   = Mojo::Redis::Protocol->new;
    my @reply_with = ({type => '$', data => 'OK'});

    push @reply_with,
      $conn_n == 0
      ? {type => '$', data => 'IDONTKNOW'}
      : {type => '*', data => [{type => '$', data => 'localhost'}, {type => '$', data => $port}]};

    my $cid = ++$conn_n;
    $protocol->on_message(sub {
      push @sent_to_server, pop;
      die if @sent_to_server > 10;
      $sent_to_server[-1]{c} = $cid;
      $stream->write($protocol->encode(shift @reply_with)) if @reply_with;
      Mojo::IOLoop->stop if $sent_to_server[-1]{data}[0] eq 'SELECT';
    });

    $stream->on(read => sub { $protocol->parse(pop) });
  }
);

my $redis = Mojo::Redis->new("redis://whatever:s3cret\@mymaster/12?sentinel=localhost:$port&sentinel=localhost:$port");
my $db    = $redis->db;
$db->connection->_connect;
Mojo::IOLoop->start;

delete @$_{qw(level size stop)} for @sent_to_server;
is_deeply(
  \@sent_to_server,
  [
    {c => 1, data => [qw(AUTH s3cret)],                               type => '*'},
    {c => 1, data => [qw(SENTINEL get-master-addr-by-name mymaster)], type => '*'},
    {c => 2, data => [qw(AUTH s3cret)],                               type => '*'},
    {c => 2, data => [qw(SENTINEL get-master-addr-by-name mymaster)], type => '*'},
    {c => 3, data => [qw(AUTH s3cret)],                               type => '*'},
    {c => 3, data => [qw(SELECT 12)],                                 type => '*'},
  ],
  'discovery + connect'
);

done_testing;
