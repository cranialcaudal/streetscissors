defmodule Web.Contact.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contact_messages" do
    field :name, :string
    field :email, :string
    field :message, :string
    field :read, :boolean, default: false
    field :status, :string, default: "inbox"

    # Set only on letters (Web.Letters): which piece it answers, whether the
    # writer allowed it to be published, and when the author chose to.
    field :piece, :string
    field :may_publish, :boolean, default: false
    field :published_at, :utc_datetime
    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:name, :email, :message, :read, :status])
    |> validate_required([:name, :email, :message])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
  end

  @doc """
  A letter: the contact message's fields, plus the piece it answers and the
  writer's consent. What a visitor submits never sets `published_at` — only
  `Web.Letters.publish/1` does — and a letter is kept to a letter's length.
  """
  def letter_changeset(message, piece, attrs) do
    message
    |> cast(attrs, [:name, :email, :message, :may_publish])
    |> put_change(:piece, piece)
    |> put_change(:status, "inbox")
    |> validate_required([:name, :email, :message, :piece])
    |> validate_length(:name, max: 120)
    |> validate_length(:message, max: 5_000)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
  end
end
