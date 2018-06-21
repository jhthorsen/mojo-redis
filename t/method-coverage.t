use Mojo::Base -strict;
use Test::More;
use Mojo::UserAgent;

use Mojo::Redis::Database;
use Mojo::Redis::PubSub;

plan skip_all => 'CHECK_METHOD_COVERAGE=1' unless $ENV{CHECK_METHOD_COVERAGE};

my $methods = Mojo::UserAgent->new->get('https://redis.io/commands')->res->dom->find('[data-name]');
my @classes = qw(Mojo::Redis::Database Mojo::Redis::PubSub);
my %skip;

$skip{$_} = 1 for qw(auth quit select);              # methods
$skip{$_} = 1 for qw(cluster hyperloglog server);    # groups

$methods = $methods->map(sub { [$_->{'data-group'}, $_->{'data-name'}] });

METHOD:
for my $t (sort { "@$a" cmp "@$b" } @$methods) {
  my $method = $t->[1];
  $method =~ s!\s!_!g;

  # Translate and/or skip methods
  $method = 'listen'   if $method =~ /subscribe$/;
  $method = 'unlisten' if $method =~ /unsubscribe$/;

  if ($skip{$t->[0]}++) {
    local $TODO = sprintf 'Add Mojo::Redis::%s', ucfirst $t->[1];
    ok 0, "not implemented: $method (@$t)";
    next METHOD;
  }
  if ($skip{$t->[1]} or $method eq 'pubsub') {
    note "Skipping @$t";
    next METHOD;
  }

REDIS_CLASS:
  for my $class (@classes) {
    next REDIS_CLASS unless $class->can($method);
    ok 1, "$class can $method (@$t)";
    next METHOD;
  }
  ok 0, "not implemented: $method (@$t)";
}

done_testing;
