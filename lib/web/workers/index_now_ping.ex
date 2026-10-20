defmodule Web.Workers.IndexNowPing do
  @moduledoc """
  One IndexNow ping (`Web.IndexNow.ping/1`). On the webmentions queue, the
  other one that talks to outside sites. A transport failure is retried; a
  refusal is not.
  """

  use Oban.Worker, queue: :webmentions, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"paths" => paths}}) do
    if Web.IndexNow.key(), do: Web.IndexNow.ping(paths), else: :ok
  end
end
