package Mailroom::Model;
use Mojo::Base -base, -signatures;

use Carp qw(croak);
use Mojo::Home;
use Mojo::Loader qw(load_class);
use Mojo::Log;
use Mojo::Server;
use Mailroom::Model::Aliases;
use Mailroom::Model::Minion;

has app => sub { $_[0]{app_ref} = Mojo::Server->new->build_app('Mojo::HelloWorld') }, weak => 1;
has 'backend';
has log => sub ($self) {
  my $logdir = Mojo::Home->new->detect->child('log');
  my $log = Mojo::Log->new;
  $log->path($logdir->child('model.log')) if -e $logdir && !$ENV{MOJO_LOG_STDERR};
  return $log;
};
has aliases => sub ($self) { Mailroom::Model::Aliases->new(model => $self) };
has minion => sub ($self) { Mailroom::Model::Minion->new(model => $self) };

sub new {
  my $self = shift->SUPER::new;
  @_ = ((map { ref ? @$_ : $_ } shift), @_);

  my $class = 'Mailroom::Backend::' . (shift || 'SQLite');
  my $e     = load_class $class;
  croak ref $e ? $e : qq{Backend "class" missing} if $e;

  return $self->backend($class->new(@_)->model($self));
}

1;