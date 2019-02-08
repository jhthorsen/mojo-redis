package Mojo::Redis::Protocol;
use Mojo::Base -base;

use Carp qw(confess croak);
use Encode 'find_encoding';

use constant DEBUG => $ENV{MOJO_REDIS_DEBUG} || 0;

has on_message => undef;

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
  $self->{buf} = '';
  return $self;
}

sub parse {
  my $self = shift;
  my $curr = $self->{curr} ||= {level => 0};
  my $buf  = \$self->{buf};
  my $encoder;

  $$buf .= shift;

CHUNK:
  while (length $$buf) {
    do { local $_ = $$buf; s!\r\n!\\r\\n!g; warn "[Mojo::Redis::Protocol] parse($_)\n" } if DEBUG > 1;

    # Look for initial type
    if (!$curr->{type}) {
      $curr->{type} = substr $$buf, 0, 1, '';
      _parse_debug(start => $curr) if DEBUG > 1;
    }

    # Simple Strings, Errors, Integers
    if ($curr->{type} eq '+' or $curr->{type} eq '-' or $curr->{type} eq ':') {
      $curr->{len} //= index $$buf, "\r\n";
      return $curr->{len} = undef if $curr->{len} < 0;    # Wait for more data

      $curr->{data} = substr $$buf, 0, $curr->{len}, '';
      substr $$buf, 0, 2, '';                             # Remove \r\n after data

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
      $curr->{stop} //= index $$buf, "\r\n";
      return $curr->{stop} = undef if $curr->{stop} < 0;    # Wait for more data

      $curr->{len} //= substr $$buf, 0, $curr->{stop}, '';
      return undef if length($$buf) - 2 < $curr->{len};     # Wait for more data

      $curr->{data} = $curr->{len} < 0 ? undef : substr $$buf, 2, $curr->{len}, '';
      $curr->{data} = $encoder->decode($curr->{data}, 0) if $encoder ||= $self->{encoder};
      substr $$buf, 0, 4, '';                               # Remove \r\n before and after data
      _parse_debug(scalar => $curr) if DEBUG > 1;
    }

    # Arrays
    elsif ($curr->{type} eq '*') {
      $curr->{stop} //= index $$buf, "\r\n";
      return $curr->{stop} = undef if $curr->{stop} < 0;    # Wait for more data

      $curr->{size} //= substr $$buf, 0, $curr->{stop}, '';
      return undef if length($$buf) - 2 < $curr->{size};    # Wait for more data

      $curr->{data} = $curr->{size} < 0 ? undef : [];
      substr $$buf, 0, 2, '';                               # Remove \r\n after array size
      _parse_debug(array => $curr) if DEBUG > 1;

      # Fill the array with data
      if ($curr->{size} > 0) {
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

      if (@{$parent->{data}} < $parent->{size}) {
        $curr = $self->{curr} = {level => $curr->{level}, parent => $parent};
        next CHUNK;
      }
      else {
        $curr = $self->{curr} = $parent;
      }
    }

    unless ($curr->{level}) {
      _parse_debug(emit => $self->{curr}) if DEBUG > 1;
      $self->on_message->($self, $self->{curr});
      $curr = $self->{curr} = {level => 0};
    }
  }

  return 1;
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

  my $protocol = Mojo::Redis::Protocol->new;

  $protocol->encoding("UTF-8");

  print $protocol->encode({...});

  $protocol->on_message(sub { ... });
  $protocol->parse($bytes);

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

  $bytes = $protocol->encode(\%data);

Takes a message structure and turns it into bytes.

=head2 new

  $protocol = Mojo::Redis::Protocol->new;

=head2 on_message

  $protocol = $protocol->on_message(sub { ... });
  $cb       = $protocol->on_message;

A callback which will receive new messages parsed by L</parse>.

=head2 parse

  $protocol->parse($bytes);

Used to parse bytest from the Redis server and call L</on_message> when a whole
message is parsed.

=head1 SEE ALSO

L<Mojo::Redis>, L<Protocol::Redis> and L<Protocol::Redis::XS>.

=cut
