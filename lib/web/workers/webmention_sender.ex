defmodule Web.Workers.WebmentionSender do
  @moduledoc """
  Tells one site that one of our posts links to it
  (`Web.Webmentions.Outgoing.deliver/1`). On the webmentions queue with the
  verifier, so a slow site never holds up mail. A definitive answer finishes
  the job; a transport failure is retried.
  """

  use Oban.Worker, queue: :webmentions, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}), do: Web.Webmentions.Outgoing.deliver(id)
end
