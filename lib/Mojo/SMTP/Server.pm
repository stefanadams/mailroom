package Mojo::SMTP::Server;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::IOLoop;

use Mojo::SMTP::Server::Connection;

use POSIX qw/setuid setgid/;

has address => '0.0.0.0';
has port => '25';

has 'config';
has minion => sub { die };

sub start {
  my $self = shift;
  warn "User or Group not defined in configuration\n" and return undef unless $self->config->{user} && $self->config->{group};
  my $server = Mojo::IOLoop->server({address => $self->address, port => $self->port}, sub {
    my ($loop, $stream, $id) = @_;
    print "New connection\n";
    $stream->timeout(30)->on(timeout => sub { warn "Connection timed out\n" });
    Mojo::SMTP::Server::Connection->new(server => $self, stream => $stream, id => $id);
  });
  print "Server started\n";
  Mojo::IOLoop->next_tick(sub { setgid($self->config->{user}); setuid($self->config->{group}); });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

1;
