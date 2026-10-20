defmodule Web.Daybook.BookTest do
  # The books' folder and the render lock are shared: not async.
  use WebWeb.ConnCase, async: false

  alias Web.Daybook.Book

  setup do
    File.rm_rf(Book.dir())
    :ok
  end

  test "a year's essays become a book in both formats, served from the year page", %{conn: conn} do
    # The fixture blog has a post dated 2026-07-01 (frontmatter-and-embeds).
    assert {:ok, [epub, pdf]} = Book.render(2026)
    assert String.ends_with?(epub, "2026.epub") and String.ends_with?(pdf, "2026.pdf")

    # The stub writes back the Markdown it was given: one chapter per post,
    # drafts never among them.
    text = File.read!(epub)
    assert text =~ "streetscissors · 2026"
    assert text =~ "\n# "
    refute text =~ "draft: true"

    html = conn |> get(~p"/daybook/2026") |> html_response(200)
    assert html =~ ~s(id="year-book-epub")

    resp = get(conn, ~p"/daybook/2026/book.pdf")
    assert response(resp, 200)
    assert [type] = get_resp_header(resp, "content-type")
    assert type =~ "application/pdf"
  end

  test "a year with no essays has no book, and its address is a 404", %{conn: conn} do
    assert {:error, :no_posts} = Book.render(1999)
    assert conn |> get(~p"/daybook/1999/book.epub") |> response(404)
  end

  test "the nightly pass renders only when something changed" do
    assert :ok = Book.run_scheduled()
    # Set the book's time back rather than waiting out a second: a render
    # would write a new file, and with it a new time.
    epub = Path.join(Book.dir(), "2026.epub")
    File.touch!(epub, {{2000, 1, 1}, {0, 0, 0}})
    assert :ok = Book.run_scheduled()
    assert File.stat!(epub).mtime == {{2000, 1, 1}, {0, 0, 0}}
  end
end
