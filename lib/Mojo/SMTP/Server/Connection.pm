package Mojo::SMTP::Server::Connection;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::Util qw/b64_decode b64_encode/;

use Crypt::Password ();

has [qw/server stream id _cmd helo username password mail_from/];
has rcpt_to => sub { [] };
has data => sub { [] };

has 'config';

sub new {
  my $self = shift->SUPER::new(@_);
  $self->_on_connect;
  $self->stream->on(read => sub {
    my ($stream, $bytes) = @_;
    #$self->log->debug($bytes);
    $self->cmd($stream, $bytes) and return if $self->_cmd;
    if ( my ($cmd) = ($bytes =~ /^(connect|ehlo|helo|auth\s+login|auth\s+plain|mail\s+from|rcpt\s+to|data|rset|vrfy|noop|size|help|debug|stop|quit|b64_encode|b64_decode)/i) ) {
      $cmd =~ s/\s+/_/g;
      $self->_cmd(lc($cmd));
      $self->cmd($stream, $bytes);
    } else {
      $bytes =~ /^(\w+)/;
      $self->write(500, "Unrecognized command: $1");
    }
  });
  return $self;
}

sub auth {
  my $self = shift;
  return 0 unless $self->username && $self->password;
  #$self->server->pg->db->select('auth', ['username'], {username => $self->username, password => Crypt::Password::password($self->password)})->rows;
warn Data::Dumper::Dumper($self->server->config->{auth});
  return 0 unless $self->server->config->{auth}->{$self->username};
  return $self->server->config->{auth}->{$self->username} eq $self->password ? 1 : 0;
}

sub cmd {
  my $self = shift;
  return unless my $cmd = $self->_cmd;
  $cmd = lc("_on_$cmd");
  $self->$cmd(@_);
}

sub finish { shift->_cmd('') }
sub na { shift->write(502, 'Not implemented')->finish }
sub ok { shift->write(250, 'OK')->finish }

sub queue {
  my $self = shift;
  if ( $self->auth ) {
    if ( $self->mail_from && @{$self->rcpt_to} && @{$self->data} ) {
      my $data = join '', @{$self->data};
      $data =~ s/^data\s*\r?\n//i;
      $data =~ s/\r?\n\.\r?\n.*$//;
      my $id = $self->server->minion->enqueue(relay => [$self->mail_from, $self->rcpt_to, $data]);
      return $self->write(250, sprintf 'OK message queued as %s', $id)->reset;
    } else {
      return $self->write(530, 'bad')->finish;
    }
  } else {
    return $self->write(530, 'no auth');
  }
}

sub reset { shift->mail_from('')->rcpt_to([])->username('')->password('')->data([]) }

sub write {
  my ($self, $code) = (shift, shift);
  my $cb = ref $_[-1] eq 'CODE' ? pop : ();
  my $write = '';
  while ( @_ ) {
    chomp(my $line = shift @_);
    $write .= sprintf "%s%s%s\n", $code, (@_?'-':' '), $line;
  }
  #$self->log->debug($write);
  $self->stream->write($write => $cb);
  return $self;
}

sub _on_connect {
  my $self = shift;
  $self->write(530, 'no') and return if @_ && $self->stream->handle->peerhost ne '127.0.0.1';
  $self->write(220, scalar localtime, scalar localtime)->finish;
}

sub _on_ehlo { shift->_on_helo(@_) }
sub _on_helo {
  my ($self, $stream, $bytes) = @_;
  $bytes =~ /^[eh][he]lo\s+(.*?)\s*\r?\n$/i;
  $self->helo($1);
  $self->write(250, "Hello $1", 'AUTH PLAIN LOGIN')->finish;
}

sub _on_b64_decode {
  my ($self, $stream, $bytes) = @_;
  $bytes =~ /^b64_decode\s+(.*?)\s*\r?\n/;
  $self->write(250, b64_decode($1))->finish;
}

sub _on_b64_encode {
  my ($self, $stream, $bytes) = @_;
  $bytes =~ /^b64_encode\s+(.*?)\s*\r?\n/;
  $self->write(250, b64_encode($1))->finish;
}

sub _on_auth_plain {
  my ($self, $stream, $bytes) = @_;
  $self->username('')->password('')->write(501, 'Authentication request canceled')->finish and return if $bytes =~ /^\*\r?\n/;
  $self->write(503, 'Already authenticated')->finish and return if $self->auth;
  #$self->write(xxx, 'Mail transaction already in progress')->finish and return if $self->mail_from || @{$self->rcpt_to};
  $self->na and return unless $self->helo;
  if ( $bytes =~ /auth\s+plain\s*(.*?)\s*\r?\n$/i ) {
    if ( $1 ) {
      my (undef, $username, $password) = split /\0/, b64_decode($1);
      $self->username($username)->password($password);
      $self->auth ? $self->write(235, 'ok, go ahead') : $self->write(500, 'bad')->username('')->password('');
      $self->finish;
    } else {
      $self->write(334, '');
    }
  } else {
    my (undef, $username, $password) = split /\0/, b64_decode($bytes);
    $self->username($username)->password($password);
    $self->auth ? $self->write(235, 'ok, go ahead') : $self->write(500, 'bad')->username('')->password('');
    $self->finish;
  }
}

sub _on_auth_login {
  my ($self, $stream, $bytes) = @_;
  $self->username('')->password('')->write(501, 'Authentication request canceled')->finish and return if $bytes =~ /^\*\r?\n/;
  $self->write(503, 'Already authenticated')->finish and return if $self->auth;
  $self->na and return unless $self->helo;
  if ( $bytes =~ /^auth\s+login\s*\r?\n$/i ) {
    $self->write(334, 'VXNlcm5hbWU6');
  } else {
    if ( !$self->username ) {
      $self->username(b64_decode($bytes));
      $self->write(334, 'UGFzc3dvcmQ6');
    } elsif ( !$self->password ) {
      $self->password(b64_decode($bytes));
      $self->auth ? $self->write(235, 'ok, go ahead') : $self->write(500, 'bad')->username('')->password('');
      $self->finish;
    }
  }
}

sub _on_starttls {
  my ($self, $stream, $bytes) = @_;
  $self->na;
}

sub _on_mail_from {
  my ($self, $stream, $bytes) = @_;
  $self->na and return unless $self->helo;
  $self->na and return unless $self->auth;
  $bytes =~ /^mail\s+from:\s*(.*?)\s*\r?\n$/i;
  $self->mail_from($1)->ok;
}

sub _on_rcpt_to {
  my ($self, $stream, $bytes) = @_;
  $self->na and return unless $self->helo;
  $self->na and return unless $self->auth;
  $bytes =~ /^rcpt\s+to:\s*(.*?)\s*\r?\n$/i;
  push @{$self->rcpt_to}, $1;
  $self->ok;
}

sub _on_data {
  my ($self, $stream, $bytes) = @_;
  $self->na and return unless $self->helo;
  $self->na and return unless $self->auth;
  $self->write(354, 'Send message content; end with <CRLF>.<CRLF>') unless @{$self->data};
  push @{$self->data}, $bytes;
  $self->queue->finish if $bytes =~ /^.\s*\r?\n$/m;
}

sub _on_noop { shift->ok }

sub _on_rset {
  my ($self, $stream, $bytes) = @_;
  $self->reset->ok;
}

sub _on_vrfy {
  my ($self, $stream, $bytes) = @_;
  $self->na;
}

sub _on_size {
  my ($self, $stream, $bytes) = @_;
  $self->na;
}

sub _on_help {
  my ($self, $stream, $bytes) = @_;
  $self->na;
}

sub _on_debug {
  my ($self, $stream, $bytes) = @_;
  $self->write(530, 'no') and return unless $self->stream->handle->peerhost eq '127.0.0.1';
  $self->write(214, $self->_cmd, $self->username, $self->password, $self->mail_from, @{$self->rcpt_to}, @{$self->data})->finish;
}

sub _on_stop {
  my ($self, $stream, $bytes) = @_;
  $self->write(530, 'no') and return unless $self->stream->handle->peerhost eq '127.0.0.1';
  $self->write(221, 'Goodbye', sub { shift->close })->finish;
  Mojo::IOLoop->timer(0.5 => sub { Mojo::IOLoop->stop if Mojo::IOLoop->is_running });
}

sub _on_quit {
  my ($self, $stream, $bytes) = @_;
  $self->write(221, 'Goodbye', sub { shift->close })->finish;
}

1;
