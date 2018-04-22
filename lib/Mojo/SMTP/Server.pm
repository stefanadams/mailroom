package Mojo::SMTP::Server;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::IOLoop;

use Mojo::SMTP::Server::Connection;

has address => '0.0.0.0';
has port => '25';

has minion => sub { die };

sub start {
  my $self = shift;
  my $server = Mojo::IOLoop->server({address => $self->address, port => $self->port}, sub {
    my ($loop, $stream, $id) = @_;
    print "New connection\n";
    $stream->timeout(30)->on(timeout => sub { warn "Connection timed out\n" });
    Mojo::SMTP::Server::Connection->new(server => $self, stream => $stream, id => $id);
  });
  print "Server started\n";
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

1;
