use Mojo::Base -strict;

BEGIN {
  $ENV{MAILROOM_DMARC}     //= 1;
  $ENV{MAILROOM_DEBUG}     //= 0;
  $ENV{MAILROOM_LOG_FILE}  //= '';
  $ENV{MAILROOM_LOG_LEVEL} //= 'warn';
}

use Mojo::File qw(curfile tempdir);
use lib curfile->dirname->sibling('lib')->to_string;
use lib curfile->dirname->sibling('local', 'lib', 'perl5')->to_string;

use Test::More;
use Test::Mojo;

use Mojo::Message::Request;

my $hw = Test::Mojo->new;

my $req = Mojo::Message::Request->new;
my $post = curfile->sibling('post')->slurp; # entire file must be crfl
$req->parse($post); # content length is important, length of entire body, not header: tail +18 t/post | wc -c

subtest 'Post Message Request' => sub {
  ok $req->is_finished, 'request is finished';
  ok $req->content->is_multipart, 'content is multipart';
};

my $headers   = $req->headers->to_hash;
my $multipart = [map { {content => $_->asset->slurp, $_->headers->to_hash->%*} } $req->content->parts->@*];

my $t = Test::Mojo->new('Mailroom' => {
  mailroom => {
    default_domain => 'examp.le',
    domain => {
      'examp.le' => [
        'john' => 'johndoe@examp.le',
        'johndoe' => 'to1@bar.com',
      ],
    },
  },
});
$t->app->home(tempdir);

subtest 'Helpers' => sub {
  is $t->app->mx(Mojo::URL->new('http://mailroom.examp.le')), 'examp.le', 'right mx domain';
  is ref $t->app->smtp, 'Mojo::SMTP::Client', 'right smtp object';
};

subtest 'Incoming' => sub {
  $t->get_ok('/')->status_is(200);
  $t->post_ok('/' => $headers => multipart => $multipart)->status_is(200)
    ->json_is('/domain', 'examp.le')
    ->json_is('/id', 1)
    ->json_is('/path', undef)
    ->json_is('/size', 770)
    ->json_is('/to', 'John Doe <to1@bar.com>');
};

done_testing;
