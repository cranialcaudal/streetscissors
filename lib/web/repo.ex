defmodule Web.Repo do
  @moduledoc """
  The connection to the database. Every read and write of a table goes through
  here (`Web.Repo.all/1`, `Web.Repo.insert/1` and so on, from Ecto). The
  database is SQLite, a single file: `tmp/db/web_dev.db` in development, and on
  the live site wherever `DATABASE_PATH` points.
  """

  use Ecto.Repo,
    otp_app: :web,
    adapter: Ecto.Adapters.SQLite3
end
