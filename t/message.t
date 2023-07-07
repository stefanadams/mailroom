use Mojo::Base -strict;

BEGIN {
  $ENV{MAILROOM_DMARC}      //= 1;
  $ENV{MAILROOM_DEBUG}      //= 0;
  $ENV{MAILROOM_CAPTURE_TX} //= 0;
  $ENV{MAILROOM_LOG_FILE}   //= '';
  $ENV{MAILROOM_LOG_LEVEL}  //= 'warn';
  $ENV{MOJO_LOG_LEVEL}      //= 'fatal';
}

use Mojo::File qw(curfile tempdir);
use lib curfile->dirname->sibling('lib')->to_string;
use lib curfile->dirname->sibling('local', 'lib', 'perl5')->to_string;

use Test::More;
use Test::Mojo;

use Mailroom::Incoming;
use Mailroom::Outgoing;
use Mojo::Log;

my $incoming = Mailroom::Incoming->new(
  connection => 'abc',
  request_id => '123',
  mx         => 'examp.le',
  make_path  => 0,
  home       => curfile->dirname,
  log        => Mojo::Log->new(level => 'fatal'),
);
my $outgoing = Mailroom::Outgoing->new(
  config     => {'examp.le' => ['j.*' => 'jd@sample.com']},
  incoming   => $incoming,
  log        => Mojo::Log->new(level => 'fatal'),
);

ok $incoming->req->is_finished;

subtest 'incoming' => sub {
  is $incoming->asset->size, 3559, 'right asset size';
  is length($incoming->req->to_string), 3559, 'right request size';
  is $incoming->path, curfile->dirname->child('spool', 'incoming', 'examp.le', 'abc.123'), 'right path';

  my $content = $incoming->req->content;
  ok $content->is_multipart, 'is multipart';
  is $content->header_size, 369, 'right header size';
  is $content->body_size, 3173, 'right body size';
  is scalar $content->parts->@*, 11, 'right number of parts';

  ok $content->headers_contain('X-Connection-Id: abc'), 'right header';
  ok $content->headers_contain('X-Request-Id: 123'), 'right header';

  ok $content->parts->[1]->body_contains('To: John Doe <johndoe@examp.le>'), 'right body';
};

subtest 'outgoing' => sub {
  my $incoming = $outgoing->incoming;
  is $incoming->asset->size, 3559, 'right asset size';
  is length($incoming->req->to_string), 3559, 'right request size';
  is $incoming->path, curfile->dirname->child('spool', 'incoming', 'examp.le', 'abc.123'), 'right path';

  my $content = $incoming->req->content;
  ok $content->is_multipart, 'is multipart';
  is $content->header_size, 369, 'right header size';
  is $content->body_size, 3173, 'right body size';
  is scalar $content->parts->@*, 11, 'right number of parts';

  is $outgoing->asset->size, 1653;
  is $outgoing->asset->path, curfile->dirname->child('spool', 'outgoing', 'examp.le', 'abc.123'), 'right path';
  ok $outgoing->asset->contains('rom: mailroom@examp.le'), 'right header';
  ok $outgoing->asset->contains('To: John Doe <jd@sample.com>'), 'right header';
  ok $outgoing->asset->contains('Reply-To: service@example.com'), 'right header';

  my $result = $outgoing->forward;
  is $result->{id}, 0;
  is $result->{err}, 'minion not available for queueing';
  ok !$result->{asset};
  is $result->{to_cc}, 'John Doe <jd@sample.com>';
};

$outgoing->asset->path->remove;
done_testing;