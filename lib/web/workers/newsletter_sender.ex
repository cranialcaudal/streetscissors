defmodule Web.Workers.NewsletterSender do
  @moduledoc """
  Sends one newsletter to one subscriber, as a background job. Sending a
  newsletter queues one of these per address (Oban queue `mailers`), so a slow
  or failing mail service never holds up the page that pressed Send, and each
  address is tried up to three times.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Web.Email
  alias Web.Mailer

  @impl Oban.Worker
  # A job queued before newsletters were Markdown carries no format: HTML.
  def perform(%Oban.Job{args: %{"email" => email, "subject" => subject, "body" => body} = args}) do
    email
    |> Email.newsletter(subject, body, Map.get(args, "format", "html"))
    |> Mailer.deliver()
  end
end
