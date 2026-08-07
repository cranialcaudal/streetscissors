defmodule Web.Repo.Migrations.AddStatusToContactMessages do
  use Ecto.Migration

  def change do
    alter table(:contact_messages) do
      # values: inbox, attention, archive
      add :status, :string, default: "inbox"
    end
  end
end
