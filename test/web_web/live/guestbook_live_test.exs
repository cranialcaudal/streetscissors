defmodule WebWeb.GuestbookLiveTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.GeneralFixtures

  alias Web.General

  setup do
    # Limits are per-IP and every test connects from the same one.
    Web.RateLimit.reset_all()
    :ok
  end

  # The answer only lives in server-side assigns; nothing in the HTML solves it.
  defp captcha_answer(view), do: :sys.get_state(view.pid).socket.assigns.captcha_answer

  defp sign(view, name, message, captcha) do
    view
    |> form("#guestbook-form", %{
      "guestbook_entry" => %{"name" => name, "message" => message},
      "captcha" => captcha
    })
    |> render_submit()
  end

  test "the form labels every field and names its action", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/guestbook")

    assert html =~ ~s(<h1 class="guestbook-title">Guestbook</h1>)
    assert html =~ "Leave a note — messages appear once approved."
    assert html =~ ~s(<span class="label mb-1">Name</span>)
    assert html =~ ~s(<span class="label mb-1">Message</span>)
    assert html =~ ~s(<label for="guestbook-captcha")
    assert html =~ "Sign the guestbook"
    # A prefix match: a nil entry in the component's class list renders as a
    # trailing space.
    assert html =~ ~s(class="grammar-button)
  end

  test "with nothing approved it invites the first signature", %{conn: conn} do
    guestbook_entry_fixture(%{approved: false, name: "Held Back", message: "Not yet"})

    {:ok, _view, html} = live(conn, ~p"/guestbook")

    assert html =~ "Be the first to sign."
    refute html =~ "Held Back"
  end

  test "approved entries print the name, the date and the message", %{conn: conn} do
    entry = guestbook_entry_fixture(%{name: "Ada Example", message: "Lovely darkroom."})

    {:ok, _view, html} = live(conn, ~p"/guestbook")

    assert html =~ ~s(<span class="guestbook-entry-name">Ada Example</span>)
    assert html =~ "Lovely darkroom."
    assert html =~ entry.inserted_at |> Calendar.strftime("%-d %b %Y") |> String.upcase()
    refute html =~ "Be the first to sign."
  end

  # The flash used to be set and never rendered, so a visitor got no answer.
  test "a wrong captcha answer is said on the page and signs nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/guestbook")

    html = sign(view, "Bot", "spam", "definitely-wrong")

    assert html =~ "Incorrect captcha. Please try again."
    assert html =~ ~s(role="alert")
    assert General.list_all_guestbook_entries() == []
  end

  test "a right answer holds the entry for approval and says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/guestbook")

    html = sign(view, "Ada", "Hello from the test.", captcha_answer(view))

    assert html =~ "Signed! Your message will appear once approved."
    assert [%{name: "Ada", approved: false}] = General.list_all_guestbook_entries()
    refute html =~ ~s(<span class="guestbook-entry-name">Ada</span>)
  end

  test "the page carries none of the old dark styling", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/guestbook")

    refute html =~ "#2563eb"
    refute html =~ "fa-spell-check"
    refute html =~ "rgba(0,0,0,0.3)"
    refute html =~ "color: white"
  end
end
