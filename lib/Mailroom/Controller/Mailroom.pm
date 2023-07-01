package Mailroom::Controller::Mailroom;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mailroom::Message;
use Mojo::JSON qw(j);
use Mojo::File qw(tempfile path);
use Mojo::Util qw(dumper md5_sum);
use Time::HiRes qw(gettimeofday tv_interval);

use constant DEBUG      => $ENV{MAILROOM_DEBUG} // 0;
use constant LOG_FILE   => $ENV{MAILROOM_LOG_FILE} ? path($ENV{MAILROOM_LOG_FILE})->tap(sub{$_->dirname->make_path}) : undef;
use constant LOG_LEVEL  => $ENV{MAILROOM_LOG_LEVEL} // 'trace';

sub incoming ($self) {
  $self->render_later;
  my $message = Mailroom::Message->new(
    log => $self->log,
    mx => $self->mx,
    config => $self->config->{mailroom}->{domain} || {},
    param => _params_to_hash($self->req->params->to_hash),
  );
  return $self->reply->ok unless $message && !$message->spam;
  if ($message->ok) {
    my $result = $self->_enqueue_message($message);
    $self->log->info(sprintf '[%s] job %s (%s bytes) queued %s successfully: %s', map {$_//''} $result->@{qw(domain id size path to)});
    $self->render(json => $result);
  } else {
    my $mx = $message->mx;
    $self->log->error("[$mx] error in message, job not queued");
    $self->render(json => {err => 'not queued', domain => $mx, to => $message->router->format('to+cc')});
  }
}

sub mailroom ($self) {
  $self->render;
}

sub _enqueue_message ($self, $message) {
  my $mx = $message->mx;
  my $asset = $message->asset;
  my $id;
  if ($self->helpers->can('minion')) {
    $id = $self->minion->enqueue(forward => [$message->router->format('from'), $message->router->format('to+cc'), [$asset->to_file->cleanup(0)->path]] => {queue => $mx});
    $self->minion->job($id)->note(size => $asset->size, unidecode => $message->unidecode);
    $self->minion->perform_jobs({queues => [$mx]}) if DEBUG;
  }
  my $result = {
    domain => $mx,
    id     => $id // 0,
    size   => $asset->size,
    path   => ($asset->is_file?$asset->path:undef),
    to     => $message->router->format('to+cc'),
    ($id ? () : (err => 'minion not available for queueing')),
  };
}

sub _params_to_hash ($params) {
  return {map { $_ => ((/^(charsets|envelope)$/ ? j($params->{$_}) : $params->{$_}) || undef) } keys %$params}
}

1;