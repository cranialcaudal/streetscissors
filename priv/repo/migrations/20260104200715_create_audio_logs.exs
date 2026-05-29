defmodule Web.Repo.Migrations.CreateAudioLogs do
  use Ecto.Migration

  def change do
    create table(:audio_logs) do
      add :title, :string
      add :stardate, :string
      add :file_path, :string
      # in seconds
      add :duration, :integer
      add :description, :text

      timestamps()
    end
  end
end
