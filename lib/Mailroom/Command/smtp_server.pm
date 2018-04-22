package Mailroom::Command::smtp_server;
use Mojo::Base 'Mojolicious::Command';

use Mojo::SMTP::Server;

has description => 'Start the Mailroom SMTP server';
has usage => sub { shift->extract_usage };

sub run {
  my $self = shift;

  my $smtp = Mojo::SMTP::Server->new(minion => $self->app->minion, config => $self->app->config);
  $smtp->start;
  print "Goodbye\n";
}

1;

=encoding utf8

=head1 NAME

Mailroom::Command::smtp_server - Start the Mailroom SMTP server

=head1 SYNOPSIS

  Usage: APPLICATION smtp_server

    ./myapp.pl smtp_server

=head1 DESCRIPTION

L<Mailroom::Command::smtp_server> Start the Mailroom SMTP sevrer.

=head1 ATTRIBUTES

L<Mailroom::Command::smtp_server> inherits all attributes from
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

L<Mailroom::Command::smtp_server> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $job->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mailroom>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut