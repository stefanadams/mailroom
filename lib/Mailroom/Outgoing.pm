package Mailroom::Outgoing;
use Mojo::Base -base, -signatures;

use Mail::DMARC::PurePerl;
use Mail::Internet;
use Mailroom::Router;
use Mojo::Asset::File;
use Mojo::File qw(path);
use Mojo::JSON qw(j);
use Mojo::Log;
use Mojo::Util qw(decode encode);
use Text::Unidecode;
### use Time::HiRes qw(time);

use constant DEBUG => $ENV{MAILROOM_DEBUG} // 0;
use constant DMARC => $ENV{MAILROOM_DMARC} // undef;

has asset    => sub { Mojo::Asset::File->new };
has config   => sub { {} };
has db       => undef, weak => 1;
has home     => sub { shift->incoming->home };
has log      => sub { Mojo::Log->new };
has max_spam => 6;
has minion   => undef, weak => 1;
has router   => \&_router;
has incoming    => sub { die "no incoming defined" };

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

sub forward ($self, $queue=undef) {
  my $mx     = $self->incoming->mx;
  my $info   = $self->info(queue => $queue || $mx);
  my $task   = $info->{task} = 'forward';
  my $router = $self->router;
  if ($self->minion) {
    if ($info->{id} = $self->minion->enqueue($task => [$router->format('from'), $router->format('to+cc'), path => $self->asset->path] => {queue => $info->{queue}})) {
      $self->log->info(sprintf '[%s] job %s (%s bytes) queued %s successfully for %s to %s', map {$_//''} $info->@{qw(queue id size outgoing task to_cc)});
      $self->minion->job($info->{id})->note(%$info);
      $self->minion->perform_jobs({queues => [$info->{queue}]}) if DEBUG;
    }
    else {
      $info->{err} = 'failed to enqueue with minion';
      $self->log->error(sprintf '[%s] job %s (%s bytes) NOT queued in %s %s: %s', map {$_//''} $info->@{qw(queue id size task outgoing to_cc)});
    }
  }
  else {
    $info->{err} = 'minion not available for queueing';
    $self->log->error(sprintf '[%s] job %s (%s bytes) minion not available to be queued in %s %s: %s', map {$_//''} $info->@{qw(queue id size task outgoing to_cc)});
  }
  return $info;
}

sub info ($self, %info) {
  return $self->{info} if $self->{info} && !keys %info;
  my $router   = $self->router;
  my $asset    = $self->asset;
  my $incoming = $self->incoming;
  my $req      = $incoming->req;
  return $self->{info} = {
    id         => 0,
    incoming   => $incoming->asset->path,
    outgoing   => $asset->path,
    from       => $router->format('from'),
    connection => $incoming->connection,
    queue      => $incoming->mx,
    request_id => $incoming->request_id,
    size       => $asset->size,
    spam_score => $req->param('spam_score'),
    subject    => $req->param('subject'),
    task       => '',
    to_cc      => $router->format('to+cc'),
    %info
  };
}

sub new {
  my $self = shift->SUPER::new(@_);
  #warn Mojo::Util::dumper($self->param) if DEBUG;
  #warn Mojo::Util::dumper($self->router) if DEBUG;
  return undef unless my $router = $self->router;
  ### $self->message_id;

  if (my $forward_to = $router->format('to')) {
    $self->log->info(sprintf '[%s] New incoming forward message, routing to: %s', $self->incoming->mx, $forward_to);
    $self->rewrite_email;
  }
  else {
    $self->log->warn(sprintf '[%s] No mailroom lookup address found for %s', $self->incoming->mx, join ',', $self->router->env_to->@*);
  }
  return $self;
}

sub ok ($self) { $self->router->rewrites && $self->asset->size }

sub rewrite_email ($self) {
  my $router  = $self->router;
  my $originally_from = $router->format('from');

  ### $self->router->rewrite_from;
  $router->from_mailroom;

  my $incoming = $self->incoming;
  my $mx       = $incoming->mx;
  my $req      = $incoming->req;
  my $subject  = $req->param('subject');
  my $email    = $req->param('email');

  my $mi = Mail::Internet->new;
  $mi->extract([map { "$_\n" } split /\n/, $email]);

  my ($from, $reply_to, $to, $cc) = map { $router->format($_) } qw/from reply-to to cc/;
  return unless $to;
  $mi->replace('From' => $from) if $from;
  $mi->replace('To' => $to) if $to;
  $mi->replace('Cc' => $cc) if $cc;
  $mi->replace('Reply-To' => $reply_to) if $reply_to;

  my $path = $self->home->child('spool', 'outgoing', $mx)->make_path->child($incoming->asset->path->basename);
  $path->remove if -e $path;
  my $asset = Mojo::Asset::File->new(path => $path, cleanup => 0);
  eval { $asset->add_chunk($mi->as_string) };
  if ($@) {
    $self->log->error(sprintf 'error writing %s: %s', $asset->path, $@);
  }
  else {
    $self->log->debug(sprintf 'wrote %d bytes to %s', $asset->size, $asset->path);
  }
  $self->asset($asset);
}

# TO DO: Capture this email and send a digest of retrievable SPAM messages to either the intended recipient or the designated admin account
# Test SPAM: XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X
sub spam ($self) {
  my $mx => $self->incoming->mx;
  my $req = $self->incoming->req;
  my $spam_score = $req->param('spam_score');
  return unless $spam_score && $spam_score >= $self->max_spam;
  $self->log->info(sprintf '[%s] SPAM', $mx);
  return {domain => $mx, spam => 1, spam_score => $spam_score, spam_score_threshold => $self->max_spam};
}

sub _params_to_hash ($params) {
  return {map { $_ => ((/^(charsets|envelope)$/ ? j($params->{$_}) : $params->{$_}) || undef) } keys %$params}
}

sub _router ($self) {
  my $mx = $self->incoming->mx;
  Mailroom::Router->new(
    mx     => $mx,
    config => $self->config->{$mx},
    param  => _params_to_hash($self->incoming->req->params->to_hash),
    db     => $self->db,
  );
}

sub _url_unescape ($str) { $str =~ s/=([0-9a-fA-F]{2})/chr hex $1/ger }

# sub _found_match ($lookup) {
#   return undef if @$lookup;
#   $self->minion->enqueue(forward => [$self->req->request_id], {queue => $domain});
#   $self->log->info(sprintf '[%s] No matches for %s -- queued status-check', $domain, _to_str($to));
#   return $self->render(json => {err => 'no match', domain => $domain, to => _to_str($to)});
# }

1;