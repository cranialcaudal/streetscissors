defmodule Web.Contact.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contact_messages" do
    field :name, :string
    field :email, :string
    field :message, :string
    field :read, :boolean, default: false
    field :status, :string, default: "inbox"
    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:name, :email, :message, :read, :status])
    |> validate_required([:name, :email, :message])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
  end
end
