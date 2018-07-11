#/usr/bin/env perl
use Mojolicious::Lite -signatures;

use Mojo::Redis;

helper redis => sub { state $r = Mojo::Redis->new };

helper cache => sub {
  my $c = shift;
  return $c->stash->{'redis.cache'} ||= $c->redis->cache->refresh($c->param('_refresh'));
};

helper compute_get_stats => sub {
  my ($c, $section) = @_;
  return $c->redis->db->info_structured_p($section ? ($section) : ());
};

get '/stats' => sub {
  my $c = shift->render_later;

  $c->cache->memoize_p($c, compute_get_stats => [$c->param('section')])->then(sub {
    $c->render(json => shift);
  })->catch(sub {
    $c->reply_exception(shift);
  });
};

app->start;
