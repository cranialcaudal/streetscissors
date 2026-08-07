defmodule Web.Workers.NewsletterSender do
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Web.Email
  alias Web.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email, "subject" => subject, "body" => body}}) do
    email
    |> Email.newsletter(subject, body)
    |> Mailer.deliver()
  end
end
