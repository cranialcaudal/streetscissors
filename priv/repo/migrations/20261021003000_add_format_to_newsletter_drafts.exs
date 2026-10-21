defmodule Web.Repo.Migrations.AddFormatToNewsletterDrafts do
  use Ecto.Migration

  # A newsletter is written in Markdown now (WebWeb.DocumentEditor). Every
  # row from before was HTML, and is kept that way: an old draft opens, and an
  # old send is listed, as what it was.
  def change do
    alter table(:newsletter_drafts) do
      add :format, :string, null: false, default: "html"
    end
  end
end
