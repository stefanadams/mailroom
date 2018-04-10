package Mailroom::Command::lookup;
use Mojo::Base 'Mojolicious::Command';

has description => 'Lookup Mailroom aliases';
has usage => sub { shift->extract_usage };

sub run {
  my $self = shift;

  foreach ( @_ ) {
    my $lookup = $self->app->lookup((/\@(.*)$/), {$_ => ''}, $_);
    say "$_: ".join ', ', map { '<'.$_->address.'>' } values %$lookup;
  }
}

1;

=encoding utf8

=head1 NAME

Mailroom::Command::lookup - Lookup mailroom aliases

=head1 SYNOPSIS

  Usage: APPLICATION lookup recipient

    ./myapp.pl lookup recipient [recipient ...]

=head1 DESCRIPTION

L<Mailroom::Command::lookup> looks up aliases in L<Mailroom>.

=head1 ATTRIBUTES

L<Mailroom::Command::lookup> inherits all attributes from
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

L<Mailroom::Command::lookup> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $job->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mailroom>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut