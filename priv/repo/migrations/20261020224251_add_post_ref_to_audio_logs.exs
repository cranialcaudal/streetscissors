defmodule Web.Repo.Migrations.AddPostRefToAudioLogs do
  use Ecto.Migration

  # The post a captain's log belongs with, as a piece ref ("post:<slug>",
  # Web.Pieces). Nullable: most logs stand alone.
  def change do
    alter table(:audio_logs) do
      add :post_ref, :string
    end
  end
end
