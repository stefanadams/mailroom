package Mailroom::Model::Aliases::Backend::SQLite;
use Mojo::Base 'Mailroom::Model::Aliases::Backend', -signatures;

has 'sqlite';

sub new {
  my $self = shift->SUPER::new(@_);
  $self->sqlite($self->model->backend->database);
  return $self;
}

sub add ($self, $recipient, $forward_to) {
  $self->sqlite->db->insert('aliases', {recipient => $recipient, forward_to => $forward_to});
}

sub domains ($self) {
  $self->sqlite->db->query(q(select distinct substr(recipient, instr(recipient, '@')+1) as domain from aliases))->hashes->map(sub{$_->{domain}})->to_array;
}

1;