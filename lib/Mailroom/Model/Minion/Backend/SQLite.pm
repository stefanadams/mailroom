package Mailroom::Model::Minion::Backend::SQLite;
use Mojo::Base 'Mailroom::Model::Minion::Backend', -signatures;

has 'sqlite';

sub new {
  my $self = shift->SUPER::new(@_);
  $self->sqlite($self->model->backend->database);
  return $self;
}


sub recently_finished ($self, $seconds=3600) {
  $self->sqlite->db->query(q(select count(*) from minion_jobs where task = 'forward' and finished > datetime('now', '-3600 seconds')))->array->[0]
}

1;