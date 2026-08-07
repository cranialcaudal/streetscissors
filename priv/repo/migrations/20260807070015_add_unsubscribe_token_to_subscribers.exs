defmodule Web.Repo.Migrations.AddUnsubscribeTokenToSubscribers do
  use Ecto.Migration

  @moduledoc """
  A durable per-subscriber unsubscribe token.

  The first implementation signed the address with `Phoenix.Token`, which is
  keyed on `secret_key_base` — so rotating that secret would silently break
  every unsubscribe link in every message already sent. Given the secret was
  just rotated once and more rotations are expected, that is the wrong
  lifetime for a link that has to keep working out of a mail archive.

  A stored random token survives key rotation, deploys and restarts.
  """

  def up do
    alter table(:subscribers) do
      add :unsubscribe_token, :string
    end

    # Backfill existing rows so no subscriber is left without a working link.
    # randomblob(16) -> 32 hex chars, distinct per row.
    execute """
    UPDATE subscribers
       SET unsubscribe_token = lower(hex(randomblob(16)))
     WHERE unsubscribe_token IS NULL
    """

    create unique_index(:subscribers, [:unsubscribe_token])
  end

  def down do
    drop unique_index(:subscribers, [:unsubscribe_token])

    alter table(:subscribers) do
      remove :unsubscribe_token
    end
  end
end
