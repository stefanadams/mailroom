package Mailroom::Controller::Aliases;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub add ($self) {
  $self->render(user => {});
}

sub auth ($self) {
  return 1 if $self->session('user.admin');
  $self->render(text => '404', status => 404);
  return undef;
}

sub edit ($self) {
  $self->render(user => $self->model->users->find($self->param('user_id')));
}

sub index ($self) {
  $self->render(users => $self->model->users->all);
}

sub remove ($self) {
  $self->model->users->remove($self->param('user_id'));
  $self->redirect_to('users');
}

sub show ($self) {
  $self->render(user => $self->model->users->find($self->param('user_id')));
}

sub store ($self) {
  my $v = $self->_validation;
  return $self->render(action => 'add', user => {}) if $v->has_error;

  my $user_id = $self->model->users->add($v->output);
  $self->redirect_to('show_user', user_id => $user_id);
}

sub update ($self) {
  my $v = $self->_validation;
  return $self->render(action => 'edit', user => {}) if $v->has_error;

  my $user_id = $self->param('user_id');
  $self->model->users->save($user_id, $v->output);
  $self->redirect_to('show_user', user_id => $user_id);
}

sub _validation ($self) {
  my $v = $self->validation;
  my $user = $self->model->users->find($self->param('user_id')) || {};
  $v->input({%$user, $v->input->%*});
  $v->required('user_id', 'not_empty');
  $v->optional('password', 'not_empty');
  $v->required('tpa_id',   'not_empty');
  $v->optional('admin',    'not_empty');
  $v->required('email',    'not_empty');
  $v->required('name',     'not_empty');
  return $v;
}

1;