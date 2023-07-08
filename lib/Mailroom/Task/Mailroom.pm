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

  $app->minion->add_task(notify  => sub { shift->finish('notify') }); # for qw/processed dropped delivered deferred bounce/;
  $app->minion->add_task(forward => sub { _forward($self, @_) });
  $app->minion->add_task(ping    => sub { _ping($self, @_) });
  $app->minion->add_task(relay   => sub { _relay($self, @_) });
}

sub _forward ($self, $job, $mail_from, $send_to, $data_type, $data) {
  return $job->finish(sprintf "[%s] pong", $job->info->{queue}) if $send_to =~ /^devnull/;
  $self->_send($job, $mail_from, $send_to, $data_type, $data);
}

sub _relay ($self, $job, $mail_from, $send_to, $data_type, $data) {
  $self->_send($job, $mail_from, $send_to, $data_type, $data);
}

sub _ping ($self, $job) {
  my $app = $job->app;
  return $job->fail('no default_domain specified') unless my $default_domain = $self->default_domain;
  return $job->fail('no queue specified') unless my $domain = $job->info->{queue};
  return $job->fail(sprintf "[%s] Failed to ping: missing apikey", $domain) unless $self->apikey;
  my @send = ();
  push @send,
    from => "devnull\@$default_domain",
    to   => "devnull\@$domain",
    data => "From: devnull\@$default_domain\r\nTo: devnull\@$domain\r\nSubject: smtp_ping\r\n\r\nSent from Mailroom";
  #warn Mojo::Util::dumper([@send]);
  my $resp = $app->smtp->send(auth => {type => 'login', login => 'apikey', password => $self->apikey}, @send, quit => 1);
  if (my $error = ref $resp ? $resp->error : 'smtp fail') {
    $job->fail(sprintf 'failed to ping %s from %s: %s', $domain, $default_domain, $error);
  }
  else {
    $job->finish(sprintf 'successfully pinged %s from %s', $domain, $default_domain);
  }
}

sub _send ($self, $job, $mail_from, $send_to, $data_type, $data) {
  my $app = $job->app;

  #my $time = time;
  # TODO: fail if bad SSL on $domain
  $data = path($data) if $data_type eq 'path';
  return $job->fail(sprintf "[%s] Unable to read %s", $job->info->{queue}, $data) unless $data && (ref $data ? -f $data && -r _ : 1);

  my $from = ((Mail::Address->parse($mail_from))[0]);
  my $to = [map { $_->address } (Mail::Address->parse(ref $send_to ? @$send_to : $send_to))];
  my @send = (
    auth => {type => 'login', login => 'apikey', password => $self->apikey},
    from => $from->address,
    to   => $to,
    data => ($data_type eq 'path' ? $data->slurp : $data),
    quit => 1,
  );
  $job->note(send => [auth => {type => 'login', login => 'apikey', password => '???'}, @send[2..6], sprintf('%s ... (%d total bytes)', substr($send[7], 0, 100), length($send[7])), @send[8..9] ]);
  #warn Mojo::Util::dumper([@send]);
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