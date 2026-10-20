defmodule Web.Guestbook.GuestbookEntry do
  @moduledoc """
  One guestbook signature: a name, a message, whether the author has approved
  it (only approved ones are shown), and a keyed hash of the signer's IP
  address (`Web.Analytics.hash_ip/1`), so the admin can see that two
  signatures came from one sender without the address itself being kept.

  A signer may also leave a way to be reached. That is **encrypted before it is
  stored** (`seal/1`, using `Web.Guestbook.Contact`), is never loaded by an
  ordinary query (`load_in_query: false`), and is hidden from logs
  (`redact: true`). Only `Web.Guestbook.guestbook_contact/1` reads it, for the
  admin, one at a time.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "guestbook_entries" do
    field :name, :string
    field :message, :string
    field :approved, :boolean, default: false
    field :ip_hash, :string

    # A way to reach the signer, if they left one. See Web.Guestbook.Contact:
    # the column holds ciphertext and no query loads it unless it asks by
    # name. `contact` is what the form carries and exists only until the
    # entry is sealed; `has_contact` is all a listing ever knows.
    field :contact_sealed, :string, load_in_query: false, redact: true
    field :contact, :string, virtual: true, redact: true
    field :has_contact, :boolean, virtual: true, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(guestbook_entry, attrs) do
    guestbook_entry
    |> cast(attrs, [:name, :message, :approved])
    |> update_change(:name, &trim/1)
    |> update_change(:message, &trim/1)
    |> validate_required([:name, :message])
    |> cast_contact(attrs)
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

  # Optional, and only what the signer typed: an email address or a phone
  # number. Blank is no contact at all, not an error.
  defp cast_contact(changeset, attrs) do
    changeset
    |> cast(attrs, [:contact])
    |> update_change(:contact, fn value ->
      case trim(value) do
        "" -> nil
        other -> other
      end
    end)
    |> validate_length(:contact, max: Web.Guestbook.Contact.max_length())
    |> validate_change(:contact, fn :contact, contact ->
      if Web.Guestbook.Contact.plausible?(contact),
        do: [],
        else: [contact: "should be an email address or a phone number, or left empty"]
    end)
  end

  @doc """
  Turns a valid changeset's `contact` into `contact_sealed`, for the insert.
  Kept out of `changeset/2` so that validating the form as it is typed never
  encrypts anything, and so the clear text is gone from the changes before
  they reach the database.
  """
  def seal(%Ecto.Changeset{valid?: true} = changeset) do
    case fetch_change(changeset, :contact) do
      {:ok, contact} when is_binary(contact) ->
        changeset
        |> put_change(:contact_sealed, Web.Guestbook.Contact.seal(contact))
        |> delete_change(:contact)

      _ ->
        changeset
    end
  end

  def seal(changeset), do: changeset
end
