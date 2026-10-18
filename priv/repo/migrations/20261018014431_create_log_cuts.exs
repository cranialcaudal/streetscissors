defmodule Web.Repo.Migrations.CreateLogCuts do
  use Ecto.Migration

  # The cutting room (Web.Cuts): a cut is a captain's log assembled from
  # several takes, prints from the archive, titles and sound, and rendered
  # into the log it makes. Its takes and sounds are its bin.
  def change do
    create table(:log_cuts) do
      add :name, :string, null: false
      add :timeline, :map, null: false, default: %{}
      add :audio_log_id, references(:audio_logs, on_delete: :nilify_all)
      add :status, :string, null: false, default: "draft"
      add :render_error, :text
      add :rendered_at, :utc_datetime

      timestamps()
    end

    create index(:log_cuts, [:audio_log_id])

    create table(:cut_media) do
      add :log_cut_id, references(:log_cuts, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :name, :string, null: false
      add :file, :string, null: false
      add :proxy, :string
      add :status, :string, null: false, default: "processing"
      add :error, :text
      add :duration_ms, :integer
      add :width, :integer
      add :height, :integer
      add :has_audio, :boolean, null: false, default: false

      timestamps()
    end

    create index(:cut_media, [:log_cut_id])
  end
end
