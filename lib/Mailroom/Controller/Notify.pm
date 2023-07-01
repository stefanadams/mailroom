package Mailroom::Controller::Notify;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub notify ($self) {
  my $domain = $self->mx or return $self->reply->not_found;
  my $json = $self->req->json;
  $self->log->info(sprintf 'logging %s /notify %s events (%s)', scalar(@$json), $domain, join ',', map { $_->{event} } @$json);
  $self->minion->enqueue($_->{event} => [$_] => {queue => $domain}) for @$json;
  $self->render(json => {notify => [map { $_->{event} } @$json], domain => $domain});
}

1;