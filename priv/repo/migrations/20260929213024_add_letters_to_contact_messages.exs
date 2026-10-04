defmodule Web.Repo.Migrations.AddLettersToContactMessages do
  use Ecto.Migration

  # A letter is a contact message about a particular piece (Web.Letters), so
  # it lands in the same admin inbox. `piece` is a Web.Pieces ref
  # ("post:<slug>", "log:<slug>", "frame:<roll>/<n>"); `may_publish` is the
  # writer's consent to show it beneath the piece; `published_at` is set only
  # when the author chooses to. Ordinary contact messages leave all three
  # empty.
  def change do
    alter table(:contact_messages) do
      add :piece, :string
      add :may_publish, :boolean, default: false, null: false
      add :published_at, :utc_datetime
    end

    create index(:contact_messages, [:piece])
  end
end
