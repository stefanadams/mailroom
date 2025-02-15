package Mailroom::Controller::Status;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub auth ($self) {
  return 1 unless $self->app->config->{mailroom}->{minion}->{admin_ui};
  return 1 if defined $self->req->url->to_abs->userinfo && $self->req->url->to_abs->userinfo eq $self->app->config->{mailroom}->{minion}->{admin_ui};
  $self->res->headers->www_authenticate('Basic');
  $self->render(text => 'authentication failed', status => 401);
  return undef;
}

sub check ($self) {
  my $queue = $self->param('queue');
  my $duration = $self->param('duration');
  my $minion = $self->app->minion;
  $self->log->debug(sprintf 'logging /status/check check task events');
  my $checks = $minion->jobs({tasks => ['check'], states => ['active', 'inactive'], queues => [$queue]});
  my $check = 0;
  while (my $info = $checks->next) {
    # warn sprintf 'checking %s', $info->{id};
    $check = $info->{id} and last;
  }
  $check ||= $minion->enqueue('check', [$duration], {queue => $queue}) if $duration;
  return $self->render(json => {error => 'no check task found'}) unless $check;
  my $job = $minion->job($check);
  my $id = $job->id;
  if ($duration) {
    # warn sprintf 'extend %s', $id;
    $job->retry({delay => $duration});
    my $info = {created => $job->info->{created}, delayed => $job->info->{delayed}, id => $id, result => $job->info->{result}, retries => $job->info->{retries}};
    $minion->broadcast('add_queue', [$queue]);
    $self->render(json => $info);
  }
  else {
    # warn sprintf 'remove %s', $id;
    $job->remove;
    $minion->broadcast('remove_queue', [$queue]);
    $self->render(json => {removed => $id});
  }
}

sub status_page ($self) { $self->redirect_to($self->app->config->{mailroom}->{external_status_page}) };

sub status ($self) {
  my $db = $self->minion->backend->sqlite->db;
  #$self->minion->backend->sqlite->db->dbh->sqlite_trace(sub { $self->log->debug(shift) });
  # my $total = $db->query(q(select count(*) from minion_jobs where queue = ? and task = ? and finished > datetime('now', ?)), $self->param('domain'), $self->param('task'), sprintf '-%d seconds', $self->param('seconds'))->array->[0];
  my $total = $db->query(q(select count(*) from minion_jobs where queue = ? and (task = 'ping' or task = ?) and finished > datetime('now', ?)), $self->param('domain'), $self->param('task'), sprintf '-%d seconds', $self->param('seconds'))->array->[0];
  #$self->minion->backend->sqlite->db->dbh->sqlite_trace(undef);
  my $exception = sprintf 'no %s mails for %s have fininshed in the past %s seconds', $self->param('task'), $self->param('domain'), $self->param('seconds');
  $self->log->debug($exception) unless $total;
  return $self->reply->exception($exception) unless $total;
  $self->render(text => $total);
}

1;