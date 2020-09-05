package Mailroom::Command::add;
use Mojo::Base 'Mojolicious::Command';

has description => 'Add Mailroom aliases';
has usage => sub { shift->extract_usage };

sub run {
  my ($self, $recipient, $forward_to) = @_;

  $self->app->db->db->insert('aliases', {recipient => $recipient, forward_to => $_}) and say "$recipient => $_" foreach split /,/, $forward_to;
}

1;

=encoding utf8

=head1 NAME

Mailroom::Command::add - Add mailroom aliases

=head1 SYNOPSIS

  Usage: APPLICATION add [ALIASES]

    ./myapp.pl add recipient forward_to[,forward_to,...]

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