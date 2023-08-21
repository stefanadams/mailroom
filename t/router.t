use Mojo::Base -strict;

use Test::More;

use Mailroom::Router;

my $config = [
  'to1' => 'to1@bar.com',
  'to2' => 'to2@bar.com',
  'to\d' => 'tod@bar.com',
  'to3' => 'to3@bar.com',
  'tomany' => ['tomany1@bar.com', 'tomany2@bar.com'],
  'tobar' => 'to1@header.com',
];
my $envelope = {
  from => 'from@envelope.com',
  to => ['to1@envelope.com', 'to2@envelope.com'],
};
my $router;

subtest 'envelope' => sub {
  $router = Mailroom::Router->new(mx => 'header.com', config => $config, param => {
    envelope => $envelope,
  });
  is $router->from->format, 'from@envelope.com';
  is $router->to->[0]->format, 'to1@bar.com';
  is $router->to->[1]->format, 'to2@bar.com';
};

subtest 'envelope and from' => sub {
  $router = Mailroom::Router->new(mx => 'header.com', config => $config, param => {
    envelope => $envelope,
    from => '"From Header" <from@header.com>',
  });
  is $router->from->format, '"From Header" <from@header.com>';
  $router->rewrite_from;
  is $router->from->format, '"From Header" <mailroom-dmarc_rejection@header.com>';
};

subtest 'to error' => sub {
  $router = Mailroom::Router->new(mx => 'header.com', config => $config, param => {
    envelope => $envelope,
    from => '"From Header" <from@header.com>',
    to => 'invalid',
  });
  is $router->to->[0], undef;
};

subtest 'to error with valid bcc' => sub {
  $router = Mailroom::Router->new(mx => 'header.com', config => $config, param => {
    envelope => $envelope,
    from => '"From Header" <from@header.com>',
    to => 'invalid',
    bcc => '"BCC1 Header" <bcc1@bar.com>, "BCC2 Header" <bcc2@bar.com>, "BCCd Header" <bcc3@bar.com>',
  });
  is $router->to->[0], undef;
  is $router->bcc->[0]->format, '"BCC1 Header" <bcc1@bar.com>';
  is $router->bcc->[1]->format, '"BCC2 Header" <bcc2@bar.com>';
  is $router->bcc->[2]->format, '"BCCd Header" <bcc3@bar.com>';
};

subtest 'envelope, from, to, and cc' => sub {
  $router = Mailroom::Router->new(mx => 'header.com', config => $config, param => {
    envelope => $envelope,
    from => '"From Header" <from@header.com>',
    to => '"To1 Header" <to1@header.com>, "To2 Header" <to2@header.com>, "Tod Header" <to3@header.com>',
    cc => '"CC1 Header" <cc1@bar.com>, "CC2 Header" <cc2@bar.com>, "CCd Header" <cc3@bar.com>',
    bcc => '"BCC1 Header" <bcc1@bar.com>, "BCC2 Header" <bcc2@bar.com>, "BCCd Header" <bcc3@bar.com>',
  });
  is $router->to->[0]->format, '"To1 Header" <to1@bar.com>';
  is $router->to->[1]->format, '"To2 Header" <to2@bar.com>';
  is $router->to->[2]->format, '"Tod Header" <tod@bar.com>';
  is $router->cc->[0]->format, '"CC1 Header" <cc1@bar.com>';
  is $router->cc->[1]->format, '"CC2 Header" <cc2@bar.com>';
  is $router->cc->[2]->format, '"CCd Header" <cc3@bar.com>';
  is $router->bcc->[0]->format, '"BCC1 Header" <bcc1@bar.com>';
  is $router->bcc->[1]->format, '"BCC2 Header" <bcc2@bar.com>';
  is $router->bcc->[2]->format, '"BCCd Header" <bcc3@bar.com>';
};

subtest 'single routes to many' => sub {
  $router = Mailroom::Router->new(mx => 'header.com', config => $config, param => {
    envelope => $envelope,
    from => '"From Header" <from@header.com>',
    to => '"Tomany Header" <tomany@header.com>',
  });
  is $router->to->[0]->format, '"Tomany Header" <tomany1@bar.com>';
  is $router->to->[1]->format, '"Tomany Header" <tomany2@bar.com>';
};

subtest 'single routes to one' => sub {
  $router = Mailroom::Router->new(mx => 'header.com', config => $config, param => {
    envelope => $envelope,
    from => '"From Header" <from@header.com>',
    to => '"Tobar Header" <tobar@header.com>',
  });
  is $router->to->[0]->format, '"Tobar Header" <to1@bar.com>';
};

subtest 'recursive lookup' => sub {
  $router = Mailroom::Router->new(mx => 'header.com', config => $config, param => {
    envelope => $envelope,
    from => '"From Header" <from@header.com>',
    to => '"Tobar Header" <tobar@header.com>, "Somebody Else" <somebody@else.com>',
  });
  is $router->to->[0]->format, '"Tobar Header" <to1@bar.com>';
  is $router->to->[1]->format, '"Somebody Else" <somebody@else.com>';
};

subtest 'none handled by the mx' => sub {
  $router = Mailroom::Router->new(mx => 'header.com', config => $config, param => {
    envelope => $envelope,
    from => '"From Header" <from@header.com>',
    to => '"Someone Else" <someone@else.com>',
  });
  is $router->to->[0]->format, '"Someone Else" <someone@else.com>';
};

subtest 'none configured' => sub {
  $router = Mailroom::Router->new(mx => 'header.com', config => $config, param => {
    envelope => $envelope,
    from => '"From Header" <from@header.com>',
    to => '"Toa Header" <toa@header.com>, "Somebody Else" <somebody@else.com>',
  });
  is $router->to->[0]->format, '"Somebody Else" <somebody@else.com>';
};

$config = [
  'c\..*' => 'csmith123@example.com',
  'diris' => 'csmith123@example.com',
  'diirs' => 'csmith123@example.com',
  'c' => 'csmith123@example.com',
  'kris' => 'csmith123@example.com',
  'diryer' => 'csmith123@example.com',
  'kryer' => 'csmith123@example.com',
  'cryer' => 'csmith123@example.com',
  'diry' => 'csmith123@example.com',
  'dirye' => 'csmith123@example.com',
  'a\..*' => 'evesmith@example.com',
  'eveley' => 'evesmith@example.com',
  'evelee' => 'evesmith@example.com',
  'eveli' => 'evesmith@example.com',
  'eve' => 'evesmith@example.com',
  'evely' => 'evesmith@example.com',
  'eveely' => 'evesmith@example.com',
  'eveleigh' => 'evesmith@example.com',
  'ee\..*' => [qw(waltersmith2@example.com samuelsmith@example.com csmith123@example.com evesmith@example.com smithfam@example.com)],
  'ee1\..*' => [qw(waltersmith2@example.com csmith123@example.com evesmith@example.com)],
  'walter' => [qw(waltersmith2@example.com csmith123@example.com evesmith@example.com)],
  'eeal' => [qw(waltersmith2@example.com csmith123@example.com evesmith@example.com)],
  'eez' => [qw(waltersmith2@example.com csmith123@example.com evesmith@example.com)],
  'ee2\..*' => [qw(samuelsmith@example.com csmith123@example.com evesmith@example.com)],
  'samuel' => [qw(samuelsmith@example.com csmith123@example.com evesmith@example.com)],
  'eeas' => [qw(samuelsmith@example.com csmith123@example.com evesmith@example.com)],
  'eex' => [qw(samuelsmith@example.com csmith123@example.com evesmith@example.com)],
  'dude' => [qw(samuelsmith@example.com csmith123@example.com evesmith@example.com)],
  'email' => 'csmith123@example.com',
  'eeail' => 'csmith123@example.com',
  'family' => 'smithfam@example.com',
  'fam' => 'smithfam@example.com',
  'well\..*' => 'abc123@place.com',
  'lol\..*' => 'xyz456@place.com',
  'bl\..*' => [qw(bl.smith@example.com abc123@place.com xyz456@place.com csmith123@example.com tsmith1@example.com)],
];

my @anything = (qw(
  -
  abc
  123
  abc123
  ABC
  ABC123
  Abc
  Abc123
  Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc123
));

subtest "deep expansion" => sub {
  foreach my $anything (@anything) {
    my $header = ["c.$anything\@header.com", "diris\@header.com", "diirs\@header.com", "c\@header.com", "kris\@header.com", "diryer\@header.com", "kryer\@header.com", "cryer\@header.com", "diry\@header.com", "dirye\@header.com", "a.$anything\@header.com", "eveley\@header.com", "evelee\@header.com", "eveli\@header.com", "eve\@header.com", "evely\@header.com", "eveely\@header.com", "eveleigh\@header.com", "ee.$anything\@header.com", "ee1.$anything\@header.com", "walter\@header.com", "eeal\@header.com", "eez\@header.com", "ee2.$anything\@header.com", "samuel\@header.com", "eeas\@header.com", "eex\@header.com", "dude\@header.com", "email\@header.com", "eeail\@header.com", "family\@header.com", "fam\@header.com", "well.$anything\@header.com", "lol.$anything\@header.com", "bl.$anything\@header.com"];
    foreach (0..$#$header) {
      next if $anything eq '-' && $header->[$_] =~ $anything;
      next if $anything ne '-' && $header->[$_] !~ $anything;
      $router = Mailroom::Router->new(mx => 'header.com', config => $config, param => {
        envelope => {
          from => 'from@envelope.com',
          to => [$header->[$_]],
        },
      });
      #diag sprintf "%s => %s", $header->[$_], ref $config->[$_+$_+1] ? join ',', $config->[$_+$_+1]->@* : $config->[$_+$_+1];
      is_deeply [map { $_->format } $router->to->@*], (ref $config->[$_+$_+1] ? $config->[$_+$_+1] : [$config->[$_+$_+1]]) or last;
    }
  }
};

done_testing;