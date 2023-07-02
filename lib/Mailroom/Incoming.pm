package Mailroom::Incoming;
use Mojo::Base -base, -signatures;

use Mojo::Asset::File;
use Mojo::Message::Request;
use Mojo::Home;
use Mojo::Log;

has [qw(connection mx request_id)] => sub { die "missing attr" };
has asset     => \&_asset;
has home      => sub { Mojo::Home->new };
has log       => sub { Mojo::Log->new };
has make_path => 1;
has path      => \&_path;
has req       => \&_req;

sub _asset ($self) {
  $self->_fix_headers;
  my $asset = Mojo::Asset::File->new(path => $self->_path, cleanup => 0);
  if (-e $asset->path && $asset->size) {
    $self->log->debug(sprintf 'skip overwriting existing incoming: %s (%d bytes)', $asset->path, $asset->size);
  }
  else {
    eval { $asset->add_chunk($self->req->to_string) };
    if ($@) {
      $self->log->error(sprintf 'error writing %s: %s', $asset->path, $@);
    }
    else {
      $self->log->debug(sprintf 'wrote %d bytes to %s', $asset->size, $asset->path);
    }
  }
  return $asset;
}

sub _fix_headers ($self) {
  $self->connection($self->_header('X-Connection-Id' => $self->connection));
  $self->request_id($self->_header('X-Request-Id' => $self->request_id));
  $self->mx($self->_header('X-Mx' => $self->mx));
  return $self;
}

sub _header ($self, $name, $value) {
  $self->req->headers->header($name) || $self->req->headers->header($name => $value)->header($name);
}

sub _path ($self) {
  $self->home->child('spool', 'incoming', $self->mx)->tap(sub { $_->make_path if $self->make_path })->child(sprintf '%s.%s', $self->connection, $self->request_id)
}

sub _req ($self) {
  my $req = Mojo::Message::Request->new->parse($self->_path->slurp);
}

1;