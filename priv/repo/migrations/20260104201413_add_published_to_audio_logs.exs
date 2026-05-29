defmodule Web.Repo.Migrations.AddPublishedToAudioLogs do
  use Ecto.Migration

  def change do
    alter table(:audio_logs) do
      add :published, :boolean, default: false, null: false
    end
  end
end
