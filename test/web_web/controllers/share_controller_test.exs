defmodule WebWeb.ShareControllerTest do
  use WebWeb.ConnCase

  alias Web.NegativesFixtures, as: Fixture

  @pixel Base.decode64!(
           "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNgAAAAAgABSK+kcQAAAABJRU5ErkJggg=="
         )

  setup do
    dir = Web.Uploads.dir("cards")
    File.rm_rf!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    :ok
  end

  describe "GET /share/post/:slug.png" do
    test "draws and serves a published post's card, cacheable for good", %{conn: conn} do
      conn = get(conn, "/share/post/keyworded-post.png?v=anything")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
      assert [_card] = File.ls!(Web.Uploads.dir("cards"))
    end

    test "the address a post's page names is one that answers", %{conn: conn} do
      html = conn |> get(~p"/blog/keyworded-post") |> html_response(200)
      [_, image] = Regex.run(~r/<meta property="og:image" content="([^"]+)"/, html)

      assert conn |> get(URI.parse(image).path <> "?" <> URI.parse(image).query) |> response(200)
    end

    test "a draft and a post that is not there are both 404", %{conn: conn} do
      assert conn |> get("/share/post/draft-post.png") |> response(404)
      assert conn |> get("/share/post/no-such-post.png") |> response(404)
      assert File.ls(Web.Uploads.dir("cards")) in [{:ok, []}, {:error, :enoent}]
    end

    # Asked for by machines, every time a link is pasted somewhere.
    test "sets no cookie and counts no visit", %{conn: conn} do
      before = Web.Repo.aggregate(Web.Analytics.Hit, :count)
      conn = get(conn, "/share/post/keyworded-post.png")

      assert get_resp_header(conn, "set-cookie") == []
      assert Web.Repo.aggregate(Web.Analytics.Hit, :count) == before
    end
  end

  describe "photographs" do
    setup do
      root = Fixture.archive!()
      {folder, slug} = Fixture.golden_roll!(root)
      File.mkdir_p!(Path.join(folder, "frames"))
      File.write!(Path.join([folder, "frames", "01.png"]), @pixel)
      File.write!(Path.join([root, "Contact Sheets", "#{slug}.png"]), @pixel)
      :ok
    end

    test "a printed frame's card is served as a JPEG", %{conn: conn} do
      conn = get(conn, "/share/frame/013/1.jpg")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    end

    test "a roll's card is served as a JPEG", %{conn: conn} do
      conn = get(conn, "/share/roll/013.jpg")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    end

    test "a frame never printed and a roll not in the archive are 404", %{conn: conn} do
      assert conn |> get("/share/frame/013/9.jpg") |> response(404)
      assert conn |> get("/share/frame/999/1.jpg") |> response(404)
      assert conn |> get("/share/roll/999.jpg") |> response(404)
    end
  end
end
