package Mailroom;
use Mojo::Base 'Mojolicious', -signatures;

use Mailroom::Model;
use Mojo::SMTP::Client;
use Mojo::File qw(tempfile);
use Mojo::Util qw(dumper encode);

use constant DEBUG      => $ENV{MAILROOM_DEBUG} // 0;
use constant LOG_FILE   => $ENV{MAILROOM_LOG_FILE} ? path($ENV{MAILROOM_LOG_FILE})->tap(sub{$_->dirname->make_path}) : undef;
use constant LOG_LEVEL  => $ENV{MAILROOM_LOG_LEVEL} // 'trace';

sub startup ($self) {
  $self->_setup_log;

  push @{$self->plugins->namespaces},  'Mailroom::Plugin';
  push @{$self->commands->namespaces}, 'Mailroom::Command';

  my $config = $self->plugin('Config' => {default => {remove_after_days => 30}});

  $self->secrets([defined $config->{secrets} && ref $config->{secrets} eq 'ARRAY' && scalar $config->{secrets}->@* ? $config->{secrets}->@* : __FILE__]);
  $self->moniker($config->{moniker}) if $config->{moniker};

  $self->helper(model      => sub { state $model = Mailroom::Model->new($config->{backend})->app($self) });
  $self->helper(mx         => \&_mx);
  $self->helper('reply.ok' => sub { shift->render(text => '', status => 200) });
  $self->helper(smtp       => \&_smtp);

  $self->plugin(Minion => $self->app->model->backend->to_hash);
  $self->plugin('Mailroom::Task::Mailroom');
  $self->plugin('CaptureTX' => {
    skip_cb => sub ($app, $tx, $stream, $bytes) {
      return 1 if substr($bytes, 0, 14) eq 'GET / HTTP/1.1';
      return 1 if substr($bytes, 0, 40) =~ m!^\w+ (/admin/minion|/notify|/status)!;
    }
  });

  my $r = $self->routes;
  $r->get('/')->to('mailroom#mailroom');
  $r->post('/')->to('mailroom#incoming');
  $r->post('/notify')->to('notify#notify');
  $r->get('/status')->to('status#status_page');
  $r->get('/status/#domain/:seconds/:task' => {seconds => 21_600, task => 'forward'})->to('status#status');

  my $admin = $r->under('/admin')->to('admin#auth');

  my $minion = $admin->under('/minion')->to('status#auth');
  $self->plugin('Minion::Admin' => {route => $minion, return_to => 'status'});

  my $users = $admin->under('/users')->to('users#auth');
  $users->get('/')->to('users#index')->name('users');
  $users->get('/add')->to('users#add')->name('add_user');
  $users->post('/')->to('users#store')->name('store_user');
  $users->get('/:user_id')->to('users#show')->name('show_user');
  $users->get('/:user_id/edit')->to('users#edit')->name('edit_user');
  $users->put('/:user_id')->to('users#update')->name('update_user');
  $users->delete('/:user_id')->to('users#remove')->name('remove_user');

  my $domains = $admin->under('/domains')->to('domains#auth');
  $domains->get('/')->to('domains#index')->name('domains');
  $domains->get('/add')->to('domains#add')->name('add_domain');
  $domains->post('/')->to('domains#store')->name('store_domain');
  $domains->get('/:domain_id')->to('domains#show')->name('show_domain');
  $domains->get('/:domain_id/edit')->to('domains#edit')->name('edit_domain');
  $domains->put('/:domain_id')->to('domains#update')->name('update_domain');
  $domains->delete('/:domain_id')->to('domains#remove')->name('remove_domain');

  my $aliases = $admin->under('/aliases')->to('aliases#auth');
  $aliases->get('/')->to('aliases#index')->name('aliases');
  $aliases->get('/add')->to('aliases#add')->name('add_alias');
  $aliases->post('/')->to('aliases#store')->name('store_alias');
  $aliases->get('/:alias_id')->to('aliases#show')->name('show_alias');
  $aliases->get('/:alias_id/edit')->to('aliases#edit')->name('edit_alias');
  $aliases->put('/:alias_id')->to('aliases#update')->name('update_alias');
  $aliases->delete('/:alias_id')->to('aliases#remove')->name('remove_alias');

  $admin->get('/message/*file' => sub ($c) { warn $c->param('file'); $c->res->headers->content_type('text/html'); $c->reply->file('/'.$c->param('file')) });

  Mojo::IOLoop->recurring(3600 => sub {
    $self->app->minion->enqueue(ping => [] => {queue => 'ping', expire => 360}) unless $self->app->model->minion->backend->recently_finished;
  });
}

sub _mx ($c, $url=undef) {
  return $c->app->config->{mailroom}->{mx} if $c->app->config->{mailroom}->{mx};
  my $domain = ($url||$c->req->url)->to_abs->host;
  my $moniker = $c->app->moniker;
  $domain =~ s/^$moniker\.// and return $domain;
}

sub _setup_log ($self) {
  $self->app->log->level(LOG_LEVEL);
  if (my $log_file = LOG_FILE) {
    $self->app->log->path($log_file);
  } elsif (-d $self->app->home->child('log')->to_string && not defined $ENV{MAILROOM_LOG_FILE}) {
    $self->app->log->path($self->app->home->child('log', $self->app->mode.'.log'));
  }
}

sub _smtp ($c) {
  my $host = $c->app->config->{mailroom}->{smtp}->{host} || 'localhost';
  state $smtp = Mojo::SMTP::Client->new(address => $host, autodie => 0);
}

1;
