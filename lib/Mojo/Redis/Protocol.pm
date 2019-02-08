package Mojo::Redis::Protocol;
use Mojo::Base -base;

use Carp qw(confess croak);
use Encode 'find_encoding';

use constant DEBUG => $ENV{MOJO_REDIS_DEBUG} || 0;

sub encode {
  my ($self, @stack) = @_;
  my $encoder = $self->{encoder};

  my $str = '';
  while (@stack) {
    my $message = shift @stack;
    my $ref     = ref $message;
    my $data    = $ref eq 'ARRAY' || !$ref ? $message : $message->{data};
    my $type    = $ref eq 'ARRAY' ? '*' : !$ref ? '$' : $message->{type};

    if ($type eq '+' or $type eq '-' or $type eq ':') {
      $data = $encoder->encode($data, 0) if $encoder;
      $str .= "$type$data\r\n";
    }
    elsif ($type eq '$') {
      if (defined $data) {
        $data = $encoder->encode($data, 0) if $encoder and $type ne ':';
        $str .= '$' . length($data) . "\r\n$data\r\n";
      }
      else {
        $str .= "\$-1\r\n";
      }
    }
    elsif ($type eq '*') {
      if (defined $data) {
        $str .= '*' . scalar(@$data) . "\r\n";
        unshift @stack, @$data;
      }
      else {
        $str .= "*-1\r\n";
      }
    }
    else {
      confess "[Mojo::Redis::Protocol] Unknown message type $type";
    }
  }

  return $str;
}

sub encoding {
  my $self = shift;
  return $self->{encoding} unless @_;
  $self->{encoding} = shift // '';
  $self->{encoder} = $self->{encoding} && find_encoding($self->{encoding});
  Carp::confess("Unknown encoding '$self->{encoding}'") if $self->{encoding} and !$self->{encoder};
  return $self;
}

sub new {
  my $self = shift->SUPER::new(@_);
  $self->encoding($self->{encoding});
  @$self{qw(buf len stop)} = ('', -1, -1);
  return $self;
}

sub parse {
  my $self = shift;
  $self->{buf} .= shift;

  my $curr = $self->{curr} ||= {level => 0};
  my $buf  = \$self->{buf};
  my ($encoder, @messages);

CHUNK:
  while (length $$buf) {
    do { local $_ = $$buf; s!\r\n!\\r\\n!g; warn "[Mojo::Redis::Protocol] parse($_)\n" } if DEBUG > 1;

    # Look for initial type
    if (!$curr->{type}) {
      @$self{qw(len stop)} = (-1, -1);
      $curr->{type} = substr $$buf, 0, 1, '';
      _parse_debug(start => $curr) if DEBUG > 1;
    }

    # Simple Strings, Errors, Integers
    if ($curr->{type} eq '+' or $curr->{type} eq '-' or $curr->{type} eq ':') {
      $self->{len} = index $$buf, "\r\n" if $self->{len} < 0;
      last CHUNK if $self->{len} < 0;    # Wait for more data

      $curr->{data} = substr $$buf, 0, $self->{len}, '';
      substr $$buf, 0, 2, '';            # Remove \r\n after data

      # Force into correct data type
      if ($curr->{type} eq ':') {
        $curr->{data} += 0;
      }
      elsif ($encoder ||= $self->{encoder}) {
        $curr->{data} = $encoder->decode($curr->{data}, 0);
      }

      _parse_debug(scalar => $curr) if DEBUG > 1;
    }

    # Bulk Strings
    elsif ($curr->{type} eq '$') {
      $self->{stop} = index $$buf, "\r\n" if $self->{stop} < 0;
      last CHUNK if $self->{stop} < 0;    # Wait for more data

      $self->{len} = substr $$buf, 0, $self->{stop}, '';
      last CHUNK if length($$buf) - 2 < $self->{len};    # Wait for more data

      $curr->{data} = $self->{len} < 0 ? undef : substr $$buf, 2, $self->{len}, '';
      $curr->{data} = $encoder->decode($curr->{data}, 0) if $encoder ||= $self->{encoder};
      substr $$buf, 0, 4, '';                            # Remove \r\n before and after data
      _parse_debug(scalar => $curr) if DEBUG > 1;
    }

    # Arrays
    elsif ($curr->{type} eq '*') {
      $self->{stop} = index $$buf, "\r\n" if $self->{stop} < 0;
      last CHUNK if $self->{stop} < 0;                   # Wait for more data

      $curr->{len} = substr $$buf, 0, $self->{stop}, '';
      last CHUNK if length($$buf) - 2 < $curr->{len};    # Wait for more data

      $curr->{data} = $curr->{len} < 0 ? undef : [];
      substr $$buf, 0, 2, '';                            # Remove \r\n after array size
      _parse_debug(array => $curr) if DEBUG > 1;

      # Fill the array with data
      if ($curr->{len} > 0) {
        $curr = $self->{curr} = {level => $curr->{level} + 1, parent => $curr};
        next CHUNK;
      }
    }

    # Should not come to this
    else {
      confess "[Mojo::Redis::Protocol] Unknown message type $curr->{type}";
    }

    # Wait for more data
    next CHUNK unless exists $curr->{data};

    # Fill parent array with data
    while (my $parent = delete $curr->{parent}) {
      push @{$parent->{data}}, $curr->{data};
      _parse_debug(parent => $parent) if DEBUG > 1;

      if (@{$parent->{data}} < $parent->{len}) {
        $curr = $self->{curr} = {level => $curr->{level}, parent => $parent};
        next CHUNK;
      }
      else {
        $curr = $self->{curr} = $parent;
      }
    }

    unless ($curr->{level}) {
      push @messages, $curr;
      _parse_debug(push => $curr) if DEBUG > 1;
      $curr = $self->{curr} = {level => 0};
    }
  }

  return @messages;
}

sub _parse_debug {
  my ($type, $item) = @_;
  local $_ = join ', ', map {"$_=$item->{$_}"} sort grep { !/^(level)$/ } keys %$item;
  s!\r\n!\\r\\n!g;
  warn "[Mojo::Redis::Protocol] ($item->{level}) $type - $_\n";
}

1;

=encoding utf8

=head1 NAME

Mojo::Redis::Protocol - Alternative to Protocol::Redis

=head1 SYNOPSIS

  use Mojo::Redis::Protocol;

  my $protocol = Mojo::Redis::Protocol->new->encoding("UTF-8");

  print $protocol->encode("foo");
  print $protocol->encode({type => "-", data => "foo"});
  print $protocol->encode(["foo", "bar", "baz"]);

  while (my $msg = $protocol->parse($bytes)) {
    ...
  }

=head1 DESCRIPTION

L<Mojo::Redis::Protocol> is a Redis protocol parser -
L<https://redis.io/topics/protocol>.

The API is currently higly EXPERIMENTAL and should probably not be used
directly by other projects. The reason for this is that L</encode>
and L</decode> is not symmetrical.

=head1 ATTRIBUTES

=head2 encoding

  $protocol = $protocol->encoding("UTF-8");
  $protocol = $protocol->encoding(undef); # same as pass-through
  $encoding = $protocol->encoding;

Used to set or read the encoding.

=head1 METHODS

=head2 encode

  $bytes = $protocol->encode($msg);

Takes a message structure and turns it into bytes.

=head2 new

  $protocol = Mojo::Redis::Protocol->new;

=head2 parse

  my $msg = $protocol->parse($bytes);

Used to parse bytes from the Redis server. Returns a hash-ref when a complete
message has been parsed.

=head1 SEE ALSO

L<Mojo::Redis>, L<Protocol::Redis> and L<Protocol::Redis::XS>.

=cut
