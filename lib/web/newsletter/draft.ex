defmodule Web.Newsletter.Draft do
  @moduledoc """
  A newsletter, before and after it goes out. While `status` is `"draft"` it
  can be edited and previewed at `/admin/newsletter`; when it is sent, the same
  row becomes the record of the send (`sent_at`, `recipient_count`).

  `format` is how `body` is written: `"markdown"` (everything composed in the
  document editor) or `"html"` (every row from before it, sent as it was).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "newsletter_drafts" do
    field :subject, :string
    field :body, :string
    field :status, :string, default: "draft"
    field :sent_at, :naive_datetime
    field :recipient_count, :integer, default: 0
    field :format, :string, default: "html"

    timestamps()
  end

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:subject, :body, :status, :sent_at, :recipient_count, :format])
    |> validate_required([:subject, :body])
    |> validate_inclusion(:format, ~w(markdown html))
  end
end
