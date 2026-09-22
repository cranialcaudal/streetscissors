defmodule Web.Repo.Migrations.AddWitnessToAudioPlays do
  use Ecto.Migration

  # A witness is an anonymous per-browser token, and a log is witnessed once
  # per browser. The unique index is what makes a replay a no-op. The rows
  # recorded before this carry no token — all of them logged against the
  # proxy's own address, so nobody can be told apart — and SQLite never
  # treats NULLs as colliding, so they stay as history and count for nothing.
  def change do
    alter table(:audio_plays) do
      add :witness, :string
    end

    create unique_index(:audio_plays, [:audio_log_id, :witness])
  end
end
