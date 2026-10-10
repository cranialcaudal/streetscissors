defmodule Web.Repo.Migrations.AudioPlaysAreViews do
  use Ecto.Migration

  # A log's figure is views now, not distinct witnesses: every row is a view,
  # and one browser may add another once Web.Audio's window has passed. So the
  # unique index that made a replay a no-op goes, and a plain one takes its
  # place for the "has this browser a recent view?" lookup.
  def change do
    drop unique_index(:audio_plays, [:audio_log_id, :witness])
    create index(:audio_plays, [:audio_log_id, :witness])
  end
end
