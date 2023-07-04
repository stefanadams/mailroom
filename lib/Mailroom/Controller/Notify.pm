package Mailroom::Controller::Notify;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub notify ($self) {
  my $domain = $self->mx or return $self->reply->not_found;
  my $json = $self->req->json;
  $self->log->debug(sprintf 'logging %s /notify %s maintenance task events (%s)', scalar(@$json), $domain, join ',', map { $_->{event} } @$json);
  return $self->reply->ok;
  my $id = $self->minion->enqueue(notify => [$domain, map { $_->{event} } @$json] => {queue => 'maintenance'});
  $self->minion->job($id)->note(events => $json);
  $self->render(json => {notify => [map { $_->{event} } @$json], domain => $domain});
}

1;