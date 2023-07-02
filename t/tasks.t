use Mojo::Base -strict;

use Test::More;

use Test::Mojo;

my $t = Test::Mojo->new('Mailroom', {
  mailroom => {
    default_domain => 'sample.com'
  },
});
ok -f $t->app->model->backend->database->db->dbh->sqlite_db_filename;

subtest 'ping' => sub {
  $t->app->minion->enqueue(ping => [] => {queue => 'ping'});
  #$t->app->minion->perform_jobs({queues => ['ping']});
  is $t->app->minion->jobs->next->{notes}->{domains}, undef;
  $t->app->model->aliases->backend->add('a@a.com' => 'b@b.com');
  is_deeply $t->app->model->backend->database->db->select('aliases')->hash, {
    "forward_to" => "b\@b.com",
    "id" => undef,
    "recipient" => "a\@a.com"
  };
  $t->app->minion->enqueue(ping => [] => {queue => 'ping'});
  $t->app->minion->perform_jobs({queues => ['ping']});
  is_deeply $t->app->minion->jobs->next->{notes}->{domains}, ['a.com'];
};

subtest 'forward' => sub {
  $t->app->minion->enqueue(forward => ['test@sample.com', 'c@c.com', data => 'test data'] => {queue => 'sample.com'});
  $t->app->minion->perform_jobs({queues => ['sample.com']});
  is_deeply $t->app->minion->jobs->next->{notes}, {
    send => [
      "auth" => {
          "login" => "apikey",
          "password" => '???',
          "type" => "login"
      },
      "from" => "test\@sample.com",
      "to" => ["c\@c.com"],
      "data" => "test data ... (9 total bytes)",
      "quit" => 1,
    ]
  };
};

subtest 'relay' => sub {
  $t->app->minion->enqueue(relay => ['test@sample.com', 'a@a.com, b@b.com', data => 'test data'] => {queue => 'sample.com'});
  $t->app->minion->perform_jobs({queues => ['sample.com']});
  is_deeply $t->app->minion->jobs->next->{notes}, {
    send => [
      "auth" => {
          "login" => "apikey",
          "password" => '???',
          "type" => "login"
      },
      "from" => "test\@sample.com",
      "to" => ["a\@a.com", "b\@b.com"],
      "data" => "test data ... (9 total bytes)",
      "quit" => 1,
    ]
  };
};

done_testing;