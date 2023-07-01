package Mailroom::Controller::Admin;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub auth ($self) {
  return 1 unless $self->app->config->{admin_ui};
  return 1 if defined $self->req->url->to_abs->userinfo && $self->req->url->to_abs->userinfo eq $self->app->config->{admin_ui};
  $self->res->headers->www_authenticate('Basic');
  $self->render(text => 'authentication failed', status => 401);
  return undef;
}

1;