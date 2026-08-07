defmodule Web.Newsletter.Draft do
  use Ecto.Schema
  import Ecto.Changeset

  schema "newsletter_drafts" do
    field :subject, :string
    field :body, :string
    field :status, :string, default: "draft"
    field :sent_at, :naive_datetime

    timestamps()
  end

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:subject, :body, :status, :sent_at])
    |> validate_required([:subject, :body])
  end
end
