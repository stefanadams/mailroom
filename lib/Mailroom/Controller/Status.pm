package Mailroom::Controller::Status;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub auth ($self) {
  return 1 unless $self->app->config->{mailroom}->{minion}->{admin_ui};
  return 1 if defined $self->req->url->to_abs->userinfo && $self->req->url->to_abs->userinfo eq $self->app->config->{mailroom}->{minion}->{admin_ui};
  $self->res->headers->www_authenticate('Basic');
  $self->render(text => 'authentication failed', status => 401);
  return undef;
}

sub status_page ($self) { $self->redirect_to($self->app->config->{mailroom}->{external_status_page}) };

sub status ($self) {
  my $db = $self->minion->backend->sqlite->db;
  #$self->minion->backend->sqlite->db->dbh->sqlite_trace(sub { $self->log->debug(shift) });
  my $total = $db->query(q(select count(*) from minion_jobs where queue = ? and task = ? and finished > datetime('now', ?)), $self->param('domain'), $self->param('task'), sprintf '-%d seconds', $self->param('seconds'))->array->[0];
  #$self->minion->backend->sqlite->db->dbh->sqlite_trace(undef);
  return $self->reply->exception(sprintf 'no %s mails for %s have fininshed in the past %s seconds', $self->param('task'), $self->param('domain'), $self->param('seconds')) unless $total;
  $self->render(text => $total);
}

1;