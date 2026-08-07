defmodule Web.Repo.Migrations.CreateAudioPlays do
  use Ecto.Migration

  def change do
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
