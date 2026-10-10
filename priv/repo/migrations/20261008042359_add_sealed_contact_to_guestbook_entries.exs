defmodule Web.Repo.Migrations.AddSealedContactToGuestbookEntries do
  use Ecto.Migration

  # An email address or phone number a signer may leave, for the author only.
  # The column never holds it in the clear: Web.General.Contact encrypts it
  # with a key derived from the site's secret, which lives in the environment
  # and not in this file, the nightly snapshots or the mirror. Whoever holds
  # a copy of the database holds ciphertext.
  def change do
    alter table(:guestbook_entries) do
      add :contact_sealed, :text
    end
  end
end
