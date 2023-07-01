package Mailroom::Backend::SQLite;
use Mojo::Base 'Mailroom::Backend';

use Mojo::File qw(path);
use Mojo::SQLite;

sub new {
  my $self = shift->SUPER::new(database => Mojo::SQLite->new(@_));
  #warn $self->database->db->dbh->sqlite_db_filename;
  my $schema = path(__FILE__)->dirname->child('resources', 'migrations', 'sqlite.sql');
  $self->database->auto_migrate(1)->migrations->name('mailroom')->from_file($schema);
  return $self;
}

1;