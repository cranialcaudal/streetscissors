defmodule Web.General.GuestbookEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "guestbook_entries" do
    field :name, :string
    field :message, :string
    field :approved, :boolean, default: false
    field :ip_address, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(guestbook_entry, attrs) do
    guestbook_entry
    |> cast(attrs, [:name, :message, :approved, :ip_address])
    |> validate_required([:name, :message])
  end
end
