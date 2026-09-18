defmodule Web.Repo.Migrations.ReworkCaptainsLogsForVideo do
  use Ecto.Migration

  @moduledoc """
  Reshapes the captain's logs from an audio-only upload archive into one that
  holds video as well, transcoded to HLS in the background.

  This drops and recreates rather than altering, which is only defensible
  because both tables are empty in every database that exists — production and
  dev both read 0 rows for `audio_logs` and `audio_plays`. Nothing is lost, and
  the result is a schema shaped for what it now holds instead of four rounds of
  ALTER sediment on top of the 2026-01 original.

  What changed and why:

    * `title` is gone. An entry is titled by the day it was recorded, so the
      title is derived, not stored. `caption` replaces it as an optional line.
    * `seq` numbers the entries within a day — the "room for more than one
      recording the same day" — and pairs with `recorded_on` in a unique index.
    * `slug` is now the date: "2026-09-18", "2026-09-18-2".
    * `file_path` becomes `media_dir`: one directory per entry, holding an HLS
      ladder or an audio rendition plus a poster. See `Web.Uploads.entry_dir/1`.
    * `status` tracks the transcode, because an entry now exists before its
      media is playable.
  """

  def up do
    drop table(:audio_plays)
    drop table(:audio_logs)

    create table(:audio_logs) do
      # Identity. The title is derived from these two, never stored.
      add :recorded_on, :date, null: false
      add :seq, :integer, null: false, default: 1
      add :slug, :string, null: false
      add :recorded_at, :utc_datetime
      add :stardate, :string

      # What it is.
      add :kind, :string, null: false, default: "video"
      add :caption, :string
      add :description, :text
      add :keywords, :string
      add :published, :boolean, null: false, default: false

      # Where the media lives and what shape it is.
      add :media_dir, :string
      add :poster_path, :string
      add :duration, :integer
      add :width, :integer
      add :height, :integer
      add :size_bytes, :integer

      # The transcode. These are inputs, not outputs: they live on the row so
      # that a restart mid-encode can pick the job up again from the database
      # alone, which is what `Web.Media.Transcoder`'s boot requeue relies on.
      add :status, :string, null: false, default: "pending"
      add :transcode_error, :text
      add :source_path, :string
      add :trim_start_ms, :integer
      add :trim_duration_ms, :integer
      add :poster_at_ms, :integer

      timestamps()
    end

    create unique_index(:audio_logs, [:slug])
    create unique_index(:audio_logs, [:recorded_on, :seq])
    # The public page lists ready-and-published entries newest first.
    create index(:audio_logs, [:published, :status, :recorded_on])

    create table(:audio_plays) do
      add :audio_log_id, references(:audio_logs, on_delete: :delete_all), null: false
      add :ip_address, :string
      add :user_agent, :string

      timestamps()
    end

    create index(:audio_plays, [:audio_log_id])
    create index(:audio_plays, [:inserted_at])
  end

  def down do
    drop table(:audio_plays)
    drop table(:audio_logs)

    create table(:audio_logs) do
      add :title, :string
      add :stardate, :string
      add :file_path, :string
      add :duration, :integer
      add :description, :text
      add :published, :boolean, default: false, null: false
      add :slug, :string
      add :keywords, :string
      add :recorded_on, :date

      timestamps()
    end

    create unique_index(:audio_logs, [:slug])

    create table(:audio_plays) do
      add :audio_log_id, references(:audio_logs, on_delete: :delete_all), null: false
      add :ip_address, :string
      add :user_agent, :string
      add :country, :string
      add :city, :string
      add :latitude, :float
      add :longitude, :float

      timestamps()
    end

    create index(:audio_plays, [:audio_log_id])
    create index(:audio_plays, [:ip_address])
    create index(:audio_plays, [:inserted_at])
  end
end
