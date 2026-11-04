defmodule Web.Repo.Migrations.RenameWitnessesToViewers do
  use Ecto.Migration

  # One word for who saw a piece: a viewer. A post's all-time readers move
  # from `page_witnesses` to `page_viewers`, and a log view's browser token
  # from `audio_plays.witness` to `audio_plays.viewer`. Data is untouched;
  # the indexes are remade under the new names.
  def up do
    drop_if_exists unique_index(:page_witnesses, [:page, :ip_hash])
    rename table(:page_witnesses), to: table(:page_viewers)
    create unique_index(:page_viewers, [:page, :ip_hash])

    drop_if_exists index(:audio_plays, [:audio_log_id, :witness])
    rename table(:audio_plays), :witness, to: :viewer
    create index(:audio_plays, [:audio_log_id, :viewer])
  end

  def down do
    drop_if_exists index(:audio_plays, [:audio_log_id, :viewer])
    rename table(:audio_plays), :viewer, to: :witness
    create index(:audio_plays, [:audio_log_id, :witness])

    drop_if_exists unique_index(:page_viewers, [:page, :ip_hash])
    rename table(:page_viewers), to: table(:page_witnesses)
    create unique_index(:page_witnesses, [:page, :ip_hash])
  end
end
