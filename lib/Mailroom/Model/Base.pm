package Mailroom::Model::Base;
use Mojo::Base -base, -signatures;

use Carp qw(croak);
use Mojo::Loader qw(load_class);

has 'backend';
has model => undef, weak => 1;

sub new {
  my $self = shift->SUPER::new(@_);

  my $class = join '::', ref $self, 'Backend', ((split /::/, ref $self->model->backend)[-1]);
  my $e     = load_class $class;
  croak ref $e ? $e : qq{Backend "class" missing} if $e;

  return $self->backend($class->new(@_)->model($self));
}

1;