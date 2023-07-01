package Mailroom::Backend;
use Mojo::Base -base, -signatures;

has model => undef, weak => 1;
has 'database';

sub to_array { [shift->_to] }

sub to_hash { +{shift->_to} }

sub _to ($self) {
  my ($name) = reverse split /::/, ref $self;
  return ($name, $self->database);
}

1;