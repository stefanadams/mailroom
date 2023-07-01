package Mailroom::Message;
use Mojo::Base -base, -signatures;

use Mail::DMARC::PurePerl;
use Mail::Internet;
use Mailroom::Router;
use Mojo::Asset::Memory;
use Mojo::Home;
use Mojo::Log;
use Text::Unidecode;
### use Time::HiRes qw(time);

use constant DEBUG => $ENV{MAILROOM_DEBUG} // 0;
use constant DMARC => $ENV{MAILROOM_DMARC} // undef;

has config => undef, weak => 1;
has db     => undef, weak => 1;
has mx     => undef;
has param  => sub { {} };
has email  => sub { shift->param->{email} };
has router => sub ($self) { Mailroom::Router->new(
  mx     => $self->mx,
  config => $self->config->{$self->mx},
  param  => $self->param,
  db     => $self->db,
)};
has unidecode  => 0;
has asset      => sub { shift->_asset };
has subject    => sub { shift->param->{subject} };
has spam_score => sub { shift->param->{spam_score} };
has spam_score_threshold => 6;
has log        => sub { Mojo::Log->new };
has home       => sub { Mojo::Home->new };
has cleanup    => 0;

### sub message_id ($self) {
###   my $email = $self->email;
###   my $router = $self->router;
###   my $message_id = sprintf '%f\@%s', time, $self->mx;
###   # write to a database who it was originally to (y@mailroom.example.com) and this message id
###   # then when relay receives a message from x@mailroom.example.com with this In-Reply-To / References message-id,
###   # it can rewrite the from to be be y@mailroom.example.com
###   $self->email("Message-ID: <$message_id>\r\n$email");
### }

sub dmarc ($self) {
  return DMARC if defined DMARC;
  return $self->{skip_dmarc} if defined $self->{skip_dmarc};
  my $mail_from = $self->router->from;
  return unless $mail_from->host;
  my $dmarc = Mail::DMARC::PurePerl->new(header_from => $mail_from->host) or return;
  return $dmarc->validate->disposition ne 'none';
}

sub new {
  my $self = shift->SUPER::new(@_);
  #warn Mojo::Util::dumper($self->param) if DEBUG;
  #warn Mojo::Util::dumper($self->router) if DEBUG;
  return undef unless $self->mx && $self->router;
  return undef unless $self->email;
  ### $self->message_id;

  $self->log->info(sprintf '[%s] New incoming forward message, envelope: %s', $self->mx, $self->router->format('to'));

  # Check DMARC, and if it looks like it's going to fail, build a new email message header
  $self->rewrite_email;# if $self->dmarc;

  return $self;
}

sub ok ($self) { $self->router->rewrites && $self->asset->size }

sub rewrite_email ($self) {
  my $originally_from = $self->router->format('from');

  ### $self->router->rewrite_from;
  $self->router->from_mailroom;

  my $mx      = $self->mx;
  my $router  = $self->router;
  my $subject = $self->subject;

  my $mi = Mail::Internet->new;
  $mi->extract([split /\n/, $self->email]);
  $mi = _fix_quoted_printable($mi);
  chomp(my $ct = $mi->get('Content-Type') || '');
  chomp(my $mv = $mi->get('MIME-Version') || '');

  ### my ($from, $to, $cc) = map { $router->format($_) } qw/from to cc/;
  my ($from, $reply_to, $to, $cc) = map { $router->format($_) } qw/from reply-to to cc/;
  my $new_header = sprintf "From: %s\r\n", $from;
  ### $new_header .= sprintf "Reply-To: %s\r\n", $originally_from;
  $new_header .= sprintf "Reply-To: %s\r\n", $reply_to;
  $new_header .= sprintf "To: %s\r\n", $to if $to;
  $new_header .= sprintf "CC: %s\r\n", $cc if $cc;
  $new_header .= "Subject: $subject\r\n" if $subject;
  $new_header .= "MIME-Version: $mv\r\n" if $mv;
  $new_header .= "Content-Type: $ct\r\n" if $ct;

  $self->email(join "\r\n", $new_header, join("\r\n", @{$mi->body}));
}

# TO DO: Capture this email and send a digest of retrievable SPAM messages to either the intended recipient or the designated admin account
# Test SPAM: XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X
sub spam ($self) {
  my $spam_score = $self->spam_score;
  return unless $spam_score && $spam_score >= $self->spam_score_threshold;
  $self->log->info(sprintf '[%s] Failed to send: SPAM', $self->mx);
  return {domain => $self->mx, spam => 1, spam_score => $spam_score, spam_score_threshold => $self->spam_score_threshold};
}

sub _asset ($self) {
  my $mx = $self->mx;
  my $email = $self->email;
  my $spool = $self->home->child('spool', 'forward', $mx);
  my $asset = Mojo::Asset::Memory->new;
  $asset->on(upgrade => sub ($mem, $file) { $file->cleanup($self->cleanup)->tmpdir($spool->make_path) });
  eval { $asset->add_chunk($email) };
  $asset->add_chunk(unidecode $email) and $self->unidecode(1) and $self->log->warn("[$mx] unidecoded") if $@;
  return $asset;
}

sub _fix_quoted_printable ($mi) {
  if ( $mi->get('Content-Transfer-Encoding') =~ /quoted-printable/ && $mi->get('Content-Type') =~ /text\/(html|plain)/ ) {
    my $body = join "\n", @{$mi->body};
    $body =~ s/=\r?\n//gs;
    #warn $body;
    $mi->body([split /\n/, _url_unescape($body)]);
    #warn Mojo::Util::dumper($mi->body);
  }
  return $mi;
}

sub _url_unescape ($str) { $str =~ s/=([0-9a-fA-F]{2})/chr hex $1/ger }

# sub _found_match ($lookup) {
#   return undef if @$lookup;
#   $self->minion->enqueue(forward => [$self->req->request_id], {queue => $domain});
#   $self->log->info(sprintf '[%s] No matches for %s -- queued status-check', $domain, _to_str($to));
#   return $self->render(json => {err => 'no match', domain => $domain, to => _to_str($to)});
# }

1;