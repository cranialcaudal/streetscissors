defmodule Web.Uploads do
  @moduledoc """
  Single source of truth for where uploaded media lives on disk.

  Both the writer (`Web.Audio.store_upload/2`) and the reader
  (`WebWeb.Plugs.MediaServe`) resolve through here, so the two can never
  drift. Configurable via `config :web, :uploads_path` — the test env points
  it at `tmp/` so a suite run never writes into `priv/static`.
  """

  @default_root Path.join(["priv", "static", "uploads"])

  @doc "Absolute-or-relative root directory holding every upload."
  def root, do: Application.get_env(:web, :uploads_path, @default_root)

  @doc "Directory for one kind of upload, e.g. `dir(\"logs\")`."
  def dir(subdir), do: Path.join(root(), subdir)

  @doc "The public URL a stored file is served at."
  def web_path(subdir, filename), do: "/uploads/#{subdir}/#{filename}"
end
