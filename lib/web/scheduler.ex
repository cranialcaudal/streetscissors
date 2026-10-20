defmodule Web.Scheduler do
  @moduledoc """
  Runs jobs on a clock, like `cron`. This module is only the scheduler itself
  (the Quantum library); the list of jobs and the times they run, all in UTC,
  is in `config/config.exs` under `config :web, Web.Scheduler`. Work that should
  survive a restart, or be retried if it fails, goes through Oban instead
  (`Web.Workers.*`).
  """

  use Quantum, otp_app: :web
end
