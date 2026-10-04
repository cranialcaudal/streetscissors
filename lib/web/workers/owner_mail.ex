defmodule Web.Workers.OwnerMail do
  @moduledoc """
  Delivers one message from the site to its author (`Web.Notify`). On the
  mailers queue with the newsletter, so it is retried with backoff when the
  provider cannot be reached.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 5

  alias Web.Email
  alias Web.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"to" => to, "subject" => subject, "body" => body}}) do
    to
    |> Email.notice(subject, body)
    |> Mailer.deliver()
  end
end
