defmodule Web.Media.NullQueue do
  @moduledoc """
  Stands in for `Web.Media.Transcoder` during the suite.

  Accepts work and does nothing with it, so a test can upload a file and
  assert on the row it produced without an ffmpeg process — even a stubbed
  one — and without the supervised queue reaching for a database connection
  the sandbox has not lent it.
  """

  def enqueue(_log_id), do: :ok
end
