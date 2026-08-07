defmodule Web.Repo.Migrations.AddIpAddressToGuestbookEntries do
  use Ecto.Migration

  def change do
    alter table(:guestbook_entries) do
      add :ip_address, :string
    end
  end
end
