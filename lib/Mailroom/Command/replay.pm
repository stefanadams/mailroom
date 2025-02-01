package Mailroom::Command::replay;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mailroom::Incoming;
use Mailroom::Outgoing;
use Mojo::Util qw(dumper);
use Mojo::Log;

use Test::More;

has description => 'replay incoming message';
has usage => sub { shift->extract_usage };

sub run {
  my ($self, $host, $connection, $request_id) = @_;
  die $self->usage unless $host && $connection && $request_id;

  my $incoming = Mailroom::Incoming->new(
    connection => $connection,
    request_id => $request_id,
    mx         => $host,
    make_path  => 0,
    # home       => curfile->dirname,
    # log        => Mojo::Log->new(level => 'fatal'),
  );

  ok $incoming->req->is_finished, 'is finished';

  ok $incoming->asset->size > 0, 'right incoming size';
  ok length($incoming->req->to_string) > 0, 'right request size';
  ok $incoming->path =~ m!spool/incoming/$host/$connection.$request_id!, 'right path';

  my $content = $incoming->req->content;
  ok $content->is_multipart == $content->is_multipart, 'right multipart';
  ok $content->header_size > 0, 'right header size';
  ok $content->body_size > 0, 'right body size';
  ok scalar $content->parts->@* >= 0, 'right number of parts';

  ok $content->headers_contain("X-Connection-Id: $connection"), 'right header';
  ok $content->headers_contain("X-Request-Id: $request_id"), 'right header';

  my $config = $self->app->config->{mailroom}->{domain};
  my $outgoing = Mailroom::Outgoing->new(
    config     => $config,
    incoming   => $incoming,
    # log        => Mojo::Log->new(level => 'fatal'),
  );

  # warn dumper $outgoing;
  ok $outgoing->asset->size > 0, 'right outgoing size';
  ok $outgoing->asset->path =~ m!spool/outgoing/$host/$connection.$request_id!, 'right path';
  $outgoing->forward('maintenance');

  # ok $outgoing->asset->contains('rom: mailroom@examp.le'), 'right header';
  # ok $outgoing->asset->contains('To: John Doe <jd@sample.com>'), 'right header';
  # ok $outgoing->asset->contains('Reply-To: service@example.com'), 'right header';
}

1;

=encoding utf8

=head1 NAME

Mailroom::Command::replay - Replay incoming message

=head1 SYNOPSIS

  Usage: APPLICATION replay

    ./myapp.pl replay host connection request_id

=head1 DESCRIPTION

L<Mailroom::Command::add> adds aliases to L<Mailroom>.

=head1 ATTRIBUTES

L<Mailroom::Command::add> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $job->description;
  $job            = $job->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $job->usage;
  $job      = $job->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mailroom::Command::add> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $job->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mailroom>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut