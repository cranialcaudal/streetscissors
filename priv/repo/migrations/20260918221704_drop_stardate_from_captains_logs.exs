defmodule Web.Repo.Migrations.DropStardateFromCaptainsLogs do
  use Ecto.Migration

  @moduledoc """
  Drops the stardate.

  It was the one piece of costume on the page — a number derived from the
  recording date and shown twice, meaning nothing. The console keeps its
  voice through its instruments, not through Trek numerology.
  """

  def up do
    alter table(:audio_logs) do
      remove :stardate
    end
  end

  def down do
    alter table(:audio_logs) do
      add :stardate, :string
    end
  end
end
