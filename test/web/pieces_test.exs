defmodule Web.PiecesTest do
  use Web.DataCase
  import Web.AudioFixtures

  alias Web.Pieces

  # Runs against the invented fixtures: blog posts in test/support/fixtures/blog
  # and roll 001 (one print, frame 1) in test/support/fixtures/negatives.

  test "a post resolves to its title and address" do
    assert {:ok,
            %{kind: :post, title: "Fixture Post With Keywords", path: "/blog/keyworded-post"}} =
             Pieces.resolve(Pieces.post("keyworded-post"))
  end

  test "a published, transcoded log resolves; a draft does not" do
    log = log_fixture(%{recorded_on: ~D[2026-07-15]})
    draft = log_fixture(%{recorded_on: ~D[2026-07-16], published: false})

    assert {:ok, %{kind: :log, path: "/logs/2026-07-15", date: ~D[2026-07-15]}} =
             Pieces.resolve(Pieces.log(log.slug))

    assert :error = Pieces.resolve(Pieces.log(draft.slug))
  end

  test "a printed frame resolves with its roll's date; an unprinted one does not" do
    assert {:ok, %{kind: :frame, path: "/negatives/roll/001/frame/1", date: ~D[2026-01-01]}} =
             Pieces.resolve(Pieces.frame("1", 1))

    assert :error = Pieces.resolve(Pieces.frame("001", 9))
  end

  test "unknown kinds and missing pieces are errors" do
    assert :error = Pieces.resolve("post:no-such-post")
    assert :error = Pieces.resolve("page:about")
    assert :error = Pieces.resolve(nil)
  end

  test "a site path maps to its canonical ref, aliases included" do
    assert {:ok, "post:keyworded-post"} = Pieces.from_path("/blog/keyworded-post/")
    assert {:ok, "log:2026-07-15"} = Pieces.from_path("/logs/2026-07-15")
    assert {:ok, "frame:013/4"} = Pieces.from_path("/negatives/roll/13/frame/4")
    assert {:ok, "frame:013/4"} = Pieces.from_path("/negatives/roll/roll013/frame/04")
    assert :error = Pieces.from_path("/about")
    assert :error = Pieces.from_path("/negatives/roll/013/frame/x")
  end
end
