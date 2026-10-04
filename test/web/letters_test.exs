defmodule Web.LettersTest do
  use Web.DataCase

  alias Web.Letters

  @piece "post:keyworded-post"
  @attrs %{"name" => "Ada", "email" => "ada@example.com", "message" => "I read this twice."}

  test "a letter is filed against a piece that exists" do
    assert {:ok, letter} = Letters.create(@piece, Map.put(@attrs, "may_publish", "true"))
    assert letter.piece == @piece
    assert letter.may_publish
    assert letter.status == "inbox"
    assert is_nil(letter.published_at)
  end

  test "a letter about a piece that doesn't exist is refused" do
    assert {:error, :unknown_piece} = Letters.create("post:no-such-post", @attrs)
    assert {:error, :unknown_piece} = Letters.create("page:about", @attrs)
  end

  test "a visitor cannot publish their own letter" do
    {:ok, letter} =
      Letters.create(@piece, Map.put(@attrs, "published_at", "2026-01-01T00:00:00Z"))

    assert is_nil(letter.published_at)
  end

  test "a letter is kept to a letter's length" do
    assert {:error, changeset} =
             Letters.create(@piece, %{@attrs | "message" => String.duplicate("a", 5_001)})

    assert %{message: [_]} = errors_on(changeset)
  end

  test "publishing needs the writer's consent" do
    {:ok, private} = Letters.create(@piece, @attrs)
    assert {:error, :not_consented} = Letters.publish(private)

    {:ok, open} = Letters.create(@piece, Map.put(@attrs, "may_publish", "true"))
    assert {:ok, _} = Letters.publish(open)

    assert [%{id: id}] = Letters.list_published(@piece)
    assert id == open.id

    {:ok, _} = Letters.unpublish(Repo.reload(open))
    assert Letters.list_published(@piece) == []
  end
end
