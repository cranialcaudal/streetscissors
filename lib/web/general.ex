defmodule Web.General do
  @moduledoc """
  The General context.
  """

  import Ecto.Query, warn: false
  alias Web.Repo

  alias Web.General.GuestbookEntry

  @doc """
  Returns the list of guestbook_entries.

  ## Examples

      iex> list_guestbook_entries()
      [%GuestbookEntry{}, ...]

  """
  def list_guestbook_entries do
    Repo.all(GuestbookEntry)
  end

  def list_approved_guestbook_entries do
    cutoff = DateTime.utc_now() |> DateTime.add(-60, :day)

    from(g in GuestbookEntry,
      where: g.approved == true,
      where: g.inserted_at > ^cutoff,
      order_by: [desc: g.inserted_at]
    )
    |> Repo.all()
  end

  def list_all_guestbook_entries do
    from(g in GuestbookEntry, order_by: [desc: g.inserted_at])
    |> Repo.all()
  end

  @doc "Signatures waiting for approval — the admin's badge and queue."
  def count_held_guestbook_entries do
    from(g in GuestbookEntry, where: g.approved == false)
    |> Repo.aggregate(:count)
  end

  def count_guestbook_entries, do: Repo.aggregate(GuestbookEntry, :count)

  def subscribe_guestbook do
    Phoenix.PubSub.subscribe(Web.PubSub, "guestbook")
  end

  @doc """
  The admin's own topic: a signature arriving is announced here the moment
  it is held, so the approval queue fills without a reload. The public topic
  above only ever hears about approved entries.
  """
  def subscribe_guestbook_admin do
    Phoenix.PubSub.subscribe(Web.PubSub, "guestbook:admin")
  end

  @doc """
  Gets a single guestbook_entry.

  Raises `Ecto.NoResultsError` if the Guestbook entry does not exist.

  ## Examples

      iex> get_guestbook_entry!(123)
      %GuestbookEntry{}

      iex> get_guestbook_entry!(456)
      ** (Ecto.NoResultsError)

  """
  def get_guestbook_entry!(id), do: Repo.get!(GuestbookEntry, id)

  @doc """
  Creates a guestbook_entry.

  ## Examples

      iex> create_guestbook_entry(%{field: value})
      {:ok, %GuestbookEntry{}}

      iex> create_guestbook_entry(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_guestbook_entry(attrs) do
    # Entries are held for approval. This used to force `approved: true` and
    # immediately broadcast to every connected viewer, so anything that got
    # past the captcha was public the instant it was posted, with delete after
    # the fact as the only remedy. Approve from /admin/guestbook.
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("approved", false)

    with {:ok, entry} <-
           %GuestbookEntry{}
           |> GuestbookEntry.changeset(attrs)
           |> Repo.insert() do
      Phoenix.PubSub.broadcast(Web.PubSub, "guestbook:admin", {:guestbook_entry_held, entry})
      # The queue only fills in front of someone who has the admin open. The
      # letter is for the days nobody does.
      Web.Notify.guestbook_signature(entry)
      {:ok, entry}
    end
  end

  @doc """
  Publishes a held entry and pushes it to everyone currently on /guestbook.
  The broadcast lives here, on approval, rather than on insert.
  """
  def approve_guestbook_entry(%GuestbookEntry{} = entry) do
    with {:ok, entry} <- update_guestbook_entry(entry, %{"approved" => true}) do
      Phoenix.PubSub.broadcast(Web.PubSub, "guestbook", {:guestbook_entry_created, entry})
      {:ok, entry}
    end
  end

  @doc "Un-publishes an entry without deleting it."
  def unapprove_guestbook_entry(%GuestbookEntry{} = entry) do
    update_guestbook_entry(entry, %{"approved" => false})
  end

  @doc """
  Updates a guestbook_entry.

  ## Examples

      iex> update_guestbook_entry(guestbook_entry, %{field: new_value})
      {:ok, %GuestbookEntry{}}

      iex> update_guestbook_entry(guestbook_entry, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_guestbook_entry(%GuestbookEntry{} = guestbook_entry, attrs) do
    guestbook_entry
    |> GuestbookEntry.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a guestbook_entry.

  ## Examples

      iex> delete_guestbook_entry(guestbook_entry)
      {:ok, %GuestbookEntry{}}

      iex> delete_guestbook_entry(guestbook_entry)
      {:error, %Ecto.Changeset{}}

  """
  def delete_guestbook_entry(%GuestbookEntry{} = guestbook_entry) do
    Repo.delete(guestbook_entry)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking guestbook_entry changes.

  ## Examples

      iex> change_guestbook_entry(guestbook_entry)
      %Ecto.Changeset{data: %GuestbookEntry{}}

  """
  def change_guestbook_entry(%GuestbookEntry{} = guestbook_entry, attrs \\ %{}) do
    GuestbookEntry.changeset(guestbook_entry, attrs)
  end
end
