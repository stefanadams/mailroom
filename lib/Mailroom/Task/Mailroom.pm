package Mailroom::Task::Mailroom;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Mail::Address;
use Mojo::File qw(path);
use Mojo::JSON qw(j);

has 'apikey';
has 'default_domain';
has remove_after_days => 30;

sub register ($self, $app, $conf) {
  my $mailroom_conf = $app->config->{mailroom};
  $self->apikey($mailroom_conf->{sendgrid}->{apikey}) if $mailroom_conf->{sendgrid};
  $self->default_domain($mailroom_conf->{default_domain}) if $mailroom_conf->{default_domain};

  $app->minion->remove_after($self->remove_after_days * 86_400);

  $app->minion->add_task($_      => sub { shift->finish($_) }) for qw/processed dropped delivered deferred bounce/;
  $app->minion->add_task(forward => sub { _forward($self, @_) });
  $app->minion->add_task(ping    => sub { _ping($self, @_) });
  $app->minion->add_task(relay   => sub { _relay($self, @_) });
}

sub _forward ($self, $job, $mail_from, $send_to, $data) {
  return $job->finish(sprintf "[%s] finished status-check", $job->info->{queue}) unless $send_to;
  $self->_send($job, $mail_from, $send_to, $data);
}

sub _relay ($self, $job, $mail_from, $send_to, $data) {
  $self->_send($job, $mail_from, $send_to, $data);
}

sub _ping ($self, $job) {
  return $job->fail('not default_domain specified') unless $self->default_domain;
  my $app = $job->app;
  my $domains = $app->model->aliases->backend->domains;
  return $job->finish('no aliases defined') unless @$domains;
  my $from = sprintf 'null@%s', $self->default_domain;
  my $to = join ', ', map { "null\@$_" } @$domains;
  $job->note(domains => $domains);
  my $data = sprintf "From: %s\r\nTo: %s\r\nSubject: smtp_ping\r\n\r\nSent from Mailroom", $from, $to;
  $self->_send($job, $from, $to, $data);
}

sub _send ($self, $job, $mail_from, $send_to, $data) {
  my $app = $job->app;

  #my $time = time;
  # TODO: fail if bad SSL on $domain
  $data = path($data->[0]) if ref $data;
  return $job->fail(sprintf "[%s] Unable to read %s", $job->info->{queue}, $data) unless $data && (ref $data ? -f $data && -r _ : 1);

  my $from = ((Mail::Address->parse($mail_from))[0]);
  my $to = [map { $_->address } (Mail::Address->parse(ref $send_to ? @$send_to : $send_to))];
  my @send = (
    auth => {type => 'login', login => 'apikey', password => $self->apikey},
    from => $from->address,
    to   => $to,
    data => (ref $data ? $data->slurp : $data),
    quit => 1,
  );
  $job->note(send => [auth => {type => 'login', login => 'apikey', password => '???'}, @send[2..9]]);
  #warn Mojo::Util::dumper({@send});
  my $sending = ref $data ? $data : sprintf '%s bytes', length($data);
  return $job->fail(sprintf "[%s] Failed to send %s: missing apikey", $job->info->{queue}, $sending) unless $self->apikey;
  my $resp = $app->smtp->send(@send);
  if (!ref $resp) {
    $job->fail(sprintf "[%s] Failed to send %s: Unexpected return code %s", $job->info->{queue}, $sending, $resp);
  } elsif ($resp->error) {
    #$job->app->log->error(sprintf "[%s(%s)] Failed to send: %s", $domain, $id, $resp->error);
    $job->fail(sprintf "[%s] Failed to send %s: %s", $job->info->{queue}, $sending, $resp->error);
  } else {
    #$job->app->log->info(sprintf "[%s(%s)] Sent successfully", $domain, $id);
    $job->finish(sprintf "[%s] Sent %s successfully: %s", $job->info->{queue}, $sending, _to_str($send_to));
    #unlink $spool;
  }

  # sleep 60;
  # my $time1 = time;
  # my $api = $job->$app->config('sendgrid')->{apikey};
  # my $result = $job->$app->ua->get("https://api.sendgrid.com/v3/suppression/blocks?start_time=$time&end_time=$time1" => {Authorization => "Bearer $api"})->result;
  # return unless 
  # my $blocks = Mojo::Collection->new($
}

sub _to_str { ref $_[0] ? j($_[0]) : $_[0] }

1;