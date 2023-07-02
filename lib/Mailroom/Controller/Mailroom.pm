package Mailroom::Controller::Mailroom;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mailroom::Incoming;
use Mailroom::Outgoing;
use Mojo::JSON qw(j);
use Mojo::File qw(tempfile path);
use Mojo::Util qw(decode dumper encode md5_sum);
use Time::HiRes qw(gettimeofday tv_interval);

use constant DEBUG      => $ENV{MAILROOM_DEBUG} // 0;
use constant LOG_FILE   => $ENV{MAILROOM_LOG_FILE} ? path($ENV{MAILROOM_LOG_FILE})->tap(sub{$_->dirname->make_path}) : undef;
use constant LOG_LEVEL  => $ENV{MAILROOM_LOG_LEVEL} // 'trace';

sub incoming ($self) {
  $self->render_later;
  my $queue    = 'maintenance' if $self->req->headers->header('X-Request-Id');
  my $incoming = Mailroom::Incoming->new(
    connection => $self->req->headers->header('X-Connection-Id') || $self->tx->connection,
    home       => $self->app->home,
    log        => $self->log,
    mx         => $self->req->headers->header('X-Mx') || $self->mx,
    req        => $self->req,
    request_id => $self->req->headers->header('X-Request-Id') || $self->req->request_id,
  );
  my $outgoing = Mailroom::Outgoing->new(
    config     => $self->config->{mailroom}->{domain},
    log        => $self->log,
    minion     => ($self->helpers->can('minion') ? $self->minion : undef),
    incoming   => $incoming,
  );
  return $self->reply->ok unless $outgoing->ok && !$outgoing->spam;
  $self->render(json => $outgoing->forward($queue));
}

sub mailroom ($self) {
  $self->render;
}

1;