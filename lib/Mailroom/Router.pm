package Mailroom::Router;
use Mojo::Base -base, -signatures;

use List::Util qw(pairs);
use Mail::Address;

has config => undef, weak => 1;
has db => undef, weak => 1;
has mx => undef;
has param => sub { {} };
has env_from => sub { shift->param->{envelope}->{from} };
has env_to => sub { shift->param->{envelope}->{to} || [] };
has env_cc => sub { shift->param->{envelope}->{cc} || [] };
has from => sub ($self) { ((Mail::Address->parse($self->param->{from} || $self->env_from))[0]) };
has to => sub ($self) { [Mail::Address->parse($self->param->{to} || join ', ', $self->env_to->@*)] };
has cc => sub ($self) { [Mail::Address->parse($self->param->{cc} || join ', ', $self->env_cc->@*)] };
has 'reply_to';

use constant DEBUG => $ENV{MAILROOM_DEBUG} // 0;

sub format ($self, $field) {
  if ($field eq 'from') {
    my $from = $self->from;
    $from->format if $from;
  }
    elsif ($field eq 'reply-to') {
    my $reply_to = $self->reply_to;
    $reply_to->format if $reply_to;
  }
  elsif ($field eq 'to') {
    my $to = $self->to;
    #$to->[0]->format(@$to[1..$#$to]) if $to;
    join ', ', map { $_->format } @$to if $to;
  }
  elsif ($field eq 'cc') {
    my $cc = $self->cc;
    #$cc->[0]->format(@$cc[1..$#$cc]) if $cc;
    join ', ', map { $_->format } @$cc if $cc;
  }
  elsif ($field =~ /^to.?cc$/) {
    my $to = $self->to || [];
    my $cc = $self->cc || [];
    #$to->[0]->format(@$to[1..$#$to], @$cc[0..$#$cc]) if $cc;
    join ', ', map { $_->format } grep { $_ } @$to, @$cc;
  }
}

sub from_mailroom ($self) {
  my $from = (Mail::Address->parse($self->param->{from} || $self->param->{envelope}->{from}))[0];
  my ($name, $email) = ($from->phrase, $from->address);
  my $mx = $self->mx;
  my $mailroom = "mailroom\@$mx";
  my $from_mailroom = Mail::Address->new($name, $mailroom, $email);
  my $reply_to = Mail::Address->new($name, $email);
  $self->from($from_mailroom)->env_from($from_mailroom->address)->reply_to($reply_to);
}

sub new {
  my $self = shift->SUPER::new(@_);
  #warn Mojo::Util::dumper($self->to);
  return unless $self->env_from && $self->env_to;
  $self->rewrite_to($self->_build_map($self->to));
  $self->rewrite_cc($self->_build_map($self->cc));
  #warn Mojo::Util::dumper($self->to);
  return $self;
}

sub rewrites { shift->{rewrites} // 0 }

sub rewrite_cc { shift->_resolve(cc => shift) }

sub rewrite_from ($self, $reason='dmarc_rejection') {
  my $mx = $self->mx;
  $self->from(Mail::Address->new($self->from->phrase, "mailroom-$reason\@$mx"));
}

sub rewrite_to { shift->_resolve(to => shift) }

sub _build_map ($self, $addresses) {
  return {map { $_->address => [$self->_lookup_config($_) || $self->_lookup_database($_)] } @$addresses}
}

sub _lookup_config ($self, $address) {
  my $config = $self->config;
  my $user = $address->user;
  foreach (pairs @$config) {
    my ($k, $v) = ($_->key, $_->value);
    return $v if $user eq $k || $user =~ qr(^$k$);
  }
  return undef;
}

sub _lookup_database ($self, $address) {
  my $config = $self->config;
  # $aliases = $db->select('aliases', ['forward_to'], {-or => [{recipient => $rcpt_to->address}, {recipient => sprintf '*@%s', $rcpt_to->host}]})->arrays->flatten->to_array;
  return undef;
}

sub _resolve ($self, $field, $map) {
  my @addresses;
  foreach my $address ($self->$field->@*) {
    my $phrase = $address->phrase;
    my $map_address = $map->{$address->address} || $address->address eq $self->mx;
    foreach (map { ref $_ eq 'ARRAY' ? @$_ : $_ } @$map_address) {
      my $address = ref $_ ? $_->address : $_;
      ++$self->{rewrites} and push @addresses, Mail::Address->new($phrase, $address) if $address;
    }
  }
  $self->$field([@addresses]);
  __SUB__->($self, $field => $self->_build_map($self->$field)) if grep { $_->host eq $self->mx } $self->$field->@*;
}

1;