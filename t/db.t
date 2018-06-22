use Mojo::Base -strict;
use Test::More;
use Mojo::Redis;

plan skip_all => 'TEST_ONLINE=redis://localhost' unless $ENV{TEST_ONLINE};

my $redis = Mojo::Redis->new($ENV{TEST_ONLINE});
my $db    = $redis->db;
my @res;

# Make sure we don't send commands if $db goes out of scope
$db->set(x => 123, sub { @res = @_[1, 2]; Mojo::IOLoop->stop });
undef $db;

# SET
$db = $redis->db;
$db->set($0 => 123, sub { @res = @_[1, 2]; Mojo::IOLoop->stop });
Mojo::IOLoop->start;
is_deeply \@res, ['', 'OK'], 'set';

# GET
$db->get($0 => sub { @res = @_[1, 2]; Mojo::IOLoop->stop });
Mojo::IOLoop->start;
is_deeply \@res, ['', '123'], 'get';

$db->get_p($0)->then(sub { @res = (then => @_) })->catch(sub { @res = (catch => @_) })->wait;
is_deeply \@res, [then => '123'], 'get_p';

# DEL
is_deeply $db->del($0), 1, 'blocking del';

# Blocking Redis methods
@res = ();
$db->del_p('some:empty:list', $0);
$db->lpush_p($0 => '456')->then(gather_cb('then'))->catch(gather_cb('catch'));
$db->blpop_p('some:empty:list', $0, 2)->then(gather_cb('popped'))->wait;
is_deeply \@res, ["then: 1", "popped: $0 456"], 'blpop_p' or diag join ', ', @res;

done_testing;

sub gather_cb {
  my $prefix = shift;
  return sub { push @res, "$prefix: @_" };
}
