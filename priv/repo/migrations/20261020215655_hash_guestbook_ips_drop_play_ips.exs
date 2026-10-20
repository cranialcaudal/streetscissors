defmodule Web.Repo.Migrations.HashGuestbookIpsDropPlayIps do
  use Ecto.Migration

  # No visitor's address is kept at rest any more.
  #
  # * `audio_plays.ip_address` was written "for reference" and never read: a
  #   view is counted by the browser's witness token. It goes.
  # * `guestbook_entries.ip_address` was shown to the admin to spot a repeat
  #   sender. It becomes `ip_hash`, the same keyed hash analytics uses, which
  #   still shows that two signatures share a sender.
  #
  # The nightly snapshots taken before this keep the old values until they
  # age out (14 days).
  def up do
    execute "DROP INDEX IF EXISTS audio_plays_ip_address_index"

    alter table(:audio_plays) do
      remove :ip_address, :string
    end

    alter table(:guestbook_entries) do
      add :ip_hash, :string
    end

    flush()

    key = salt()

    %{rows: rows} =
      repo().query!("SELECT id, ip_address FROM guestbook_entries WHERE ip_address IS NOT NULL")

    for [id, ip] <- rows do
      hash = :crypto.mac(:hmac, :sha256, key, ip) |> Base.encode16()
      repo().query!("UPDATE guestbook_entries SET ip_hash = ?1 WHERE id = ?2", [hash, id])
    end

    alter table(:guestbook_entries) do
      remove :ip_address, :string
    end
  end

  def down do
    raise Ecto.MigrationError,
      message: "the addresses were hashed or dropped; restore from a snapshot taken before"
  end

  # Must match Web.Analytics.hash_ip/1. Written out here so a later change to
  # that module cannot change what this migration did.
  defp salt do
    secret =
      Application.get_env(:web, WebWeb.Endpoint)[:secret_key_base] ||
        raise "secret_key_base is unset; the guestbook's addresses cannot be hashed"

    :crypto.mac(:hmac, :sha256, secret, "analytics/ip/v1")
  end
end
