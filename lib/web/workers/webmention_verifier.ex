defmodule Web.Workers.WebmentionVerifier do
  @moduledoc """
  Fetches a webmention's source and records whether it really links to us
  (`Web.Webmentions.verify/1`). Runs on its own small queue so a slow site
  never holds up newsletter mail. Definitive answers finish the job; a
  transport failure is retried.
  """

  use Oban.Worker, queue: :webmentions, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}), do: Web.Webmentions.verify(id)
end
