defmodule Web.Repo.Migrations.CreateGuestbookEntries do
  use Ecto.Migration

  def change do
    create table(:guestbook_entries) do
      add :name, :string
      add :message, :text
      add :approved, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
