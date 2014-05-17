package App::Netdisco::Daemon::Worker::Common;

use Dancer qw/:moose :syntax :script/;
use Try::Tiny;

use Role::Tiny;
use namespace::clean;

with 'App::Netdisco::Daemon::JobQueue';

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  my $type = $self->worker_type;
  my $name = $self->worker_name;

  while (1) {
      debug "$type ($wid): asking for a job";
      my $jobs = $self->do('take_jobs', $self->wid, $name);

      foreach my $job (@$jobs) {
          my $target = $self->munge_action($job->action);

          try {
              $job->started(scalar localtime);
              info sprintf "$type (%s): starting %s job(%s) at %s",
                $wid, $target, $job->id, $job->started;
              my ($status, $log) = $self->$target($job);
              $job->status($status);
              $job->log($log);
          }
          catch {
              $job->status('error');
              $job->log("error running job: $_");
              $self->sendto('stderr', $job->log ."\n");
          };

          $self->close_job($job);
      }

      debug "$type ($wid): sleeping now...";
      sleep(1);
  }
}

sub close_job {
  my ($self, $job) = @_;
  my $type = $self->worker_type;
  my $now = scalar localtime;

  info sprintf "$type (%s): wrapping up %s job(%s) - status %s at %s",
    $self->wid, $job->action, $job->id, $job->status, $now;

  try {
      if ($job->status eq 'defer') {
          $self->jq_defer($job);
      }
      else {
          $job->finished($now);
          $self->jq_complete($job);
      }
  }
  catch { $self->sendto('stderr', "error closing job: $_\n") };
}

1;
