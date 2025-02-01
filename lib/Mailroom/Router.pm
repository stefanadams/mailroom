package Mailroom::Router;
use Mojo::Base -base, -signatures;

use List::Util qw(pairs);
use Mail::Address;
use Scalar::Util qw(blessed);

use constant DEBUG => $ENV{MAILROOM_DEBUG} // 0;

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
has bcc => sub ($self) { [Mail::Address->parse($self->param->{bcc})] };
has forward_to => sub { {} };
has 'reply_to';

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
  elsif ($field eq 'bcc') {
    my $bcc = $self->bcc;
    #$bcc->[0]->format(@$bcc[1..$#$bcc]) if $bcc;
    join ', ', map { $_->format } @$bcc if $bcc;
  }
  elsif ($field =~ /^to.?cc$/) {
    my $to = $self->to || [];
    my $cc = $self->cc || [];
    #$to->[0]->format(@$to[1..$#$to], @$cc[0..$#$cc]) if $cc;
    join ', ', map { $_->format } grep { $_ } @$to, @$cc;
  }
  elsif ($field eq 'forward_to') {
    join ', ', keys %{$self->forward_to};
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
  #warn Mojo::Util::dumper({env_to => $self->env_to, to => $self->to}) if DEBUG;
  return unless $self->env_from && $self->env_to;
  $self->rewrite_to($self->_build_map($self->to));
  $self->rewrite_cc($self->_build_map($self->cc));
  $self->rewrite_bcc($self->_build_map($self->bcc));
  #warn Mojo::Util::dumper({env_to => $self->env_to, to => $self->to}) if DEBUG;
  return $self;
}

sub rewrites { shift->{rewrites} // 0 }

sub rewrite_bcc { shift->_resolve(bcc => shift) }

sub rewrite_cc { shift->_resolve(cc => shift) }

sub rewrite_from ($self, $reason='dmarc_rejection') {
  my $mx = $self->mx;
  $self->from(Mail::Address->new($self->from->phrase, "mailroom-$reason\@$mx"));
}

sub rewrite_to { shift->_resolve(to => shift) }

sub _build_map ($self, $addresses) {
  return {map { $_->address => [$self->_lookup_config($_) || $self->_lookup_database($_) || ()] } @$addresses}
}

sub _lookup_config ($self, $address) {
  return undef unless my $mx = $self->mx;
  my ($user, $host) = ($address->user, $address->host);
  return undef unless $host;
  return undef unless $host eq $mx;
  my $config = $self->config;
  foreach (pairs @$config) {
    my ($k, $v) = ($_->key, $_->value);
    return $v if $user =~ qr/^$k$/i;
  }
  return undef;
}

sub _lookup_database ($self, $address) {
  my $config = $self->config;
  # $aliases = $db->select('aliases', ['forward_to'], {-or => [{recipient => $rcpt_to->address}, {recipient => sprintf '*@%s', $rcpt_to->host}]})->arrays->flatten->to_array;
  return undef;
}

sub _resolve ($self, $field, $map) {
  my @outgoing_addresses;
  foreach my $incoming_address ($self->$field->@*) {
    my $phrase = $incoming_address->phrase;
    my $lookup = $map->{$incoming_address->address};
    my $map_address = @$lookup ? $lookup : [$incoming_address];
    #my $map_address = $map->{$incoming_address->address} || $incoming_address->address eq $self->mx;
    foreach (map { ref eq 'ARRAY' ? @$_ : $_ } @$map_address) {
      my $outgoing_address = blessed($_) ? $_->address : $_;
      my $mail_address = Mail::Address->new($phrase, $outgoing_address);
      next unless $mail_address->host;
      next if $self->{$mail_address->address};
      ++$self->{rewrites} and push @outgoing_addresses, $mail_address if $outgoing_address;
      ++$self->{forward_to}->{$outgoing_address} and ++$self->{$mail_address->address} if $incoming_address->host eq $self->mx;
    }
  }
  $self->$field([@outgoing_addresses]);
  __SUB__->($self, $field => $self->_build_map($self->$field)) if grep { $_->host eq $self->mx } $self->$field->@*;
}

1;