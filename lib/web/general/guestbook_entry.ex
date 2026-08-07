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
    |> update_change(:name, &trim/1)
    |> update_change(:message, &trim/1)
    |> validate_required([:name, :message])
    # There were no bounds at all before: a submission could carry megabytes,
    # and LiveView events arrive over the websocket so Plug.Parsers' body limit
    # never applied to them.
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:message, min: 1, max: 2_000)
  end

  # cast/3 can record an explicit nil change, which String.trim/1 would raise
  # on — let validate_required report it instead.
  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end
