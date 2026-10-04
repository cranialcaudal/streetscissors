defmodule Web.Letters do
  @moduledoc """
  Letters: a reader writing to the author about one particular piece.

  The answer to "a way to know they were seen" that a comment thread gets
  wrong. A letter is signed (a name, and an email that is never shown), it is
  addressed to a person rather than posted to a crowd, and it appears beneath
  the piece only when **both** agree: the writer ticked "you may publish
  this", and the author then chose to. Everything else stays private
  correspondence.

  A letter is a `Web.Contact.Message` with a `piece` (a `Web.Pieces` ref), so
  it arrives in the admin inbox beside the contact page's messages and counts
  toward the same badge. Nothing is emailed on arrival, like the contact page.
  """

  import Ecto.Query, warn: false

  alias Web.Contact.Message
  alias Web.Pieces
  alias Web.Repo

  @doc "A blank letter changeset for a piece's form."
  def change_letter(piece, attrs \\ %{}),
    do: Message.letter_changeset(%Message{}, piece, attrs)

  @doc """
  Files a letter about `piece`. The piece must exist and be public — a letter
  about a draft, or a made-up ref, is refused.
  """
  def create(piece, attrs) do
    case Pieces.resolve(piece) do
      {:ok, _piece} ->
        piece
        |> change_letter(attrs)
        |> Repo.insert()

      :error ->
        {:error, :unknown_piece}
    end
  end

  @doc "The letters published beneath a piece, oldest first, so they read as correspondence."
  def list_published(piece) when is_binary(piece) do
    from(m in Message,
      where: m.piece == ^piece and not is_nil(m.published_at),
      order_by: [asc: m.published_at]
    )
    |> Repo.all()
  end

  @doc "Publishes a letter beneath its piece — only if its writer allowed it."
  def publish(%Message{piece: piece, may_publish: true} = letter) when is_binary(piece) do
    letter
    |> Ecto.Changeset.change(published_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  def publish(%Message{}), do: {:error, :not_consented}
  def publish(nil), do: {:error, :not_found}

  def unpublish(%Message{} = letter) do
    letter
    |> Ecto.Changeset.change(published_at: nil)
    |> Repo.update()
  end

  def unpublish(nil), do: {:error, :not_found}

  @doc "True for a contact message that is a letter about a piece."
  def letter?(%Message{piece: piece}), do: is_binary(piece)
end
