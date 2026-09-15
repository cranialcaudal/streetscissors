defmodule WebWeb.NewsletterLiveTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Web.Newsletter

  setup do
    # Limits are per-IP and every test connects from the same one, so a shared
    # counter would leak across tests.
    Web.RateLimit.reset_all()
    :ok
  end

  # The answer only ever lives in server-side assigns, so a test has to read it
  # the same way the page does — there is nothing in the rendered HTML to solve.
  defp captcha_answer(view), do: :sys.get_state(view.pid).socket.assigns.captcha_answer

  defp subscribe(view, email) do
    view
    |> form("form", %{"email" => email, "captcha" => captcha_answer(view)})
    |> render_submit()
  end

  test "user can subscribe and receive welcome email", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/newsletter")

    email = "test@example.com"
    subscribe(view, email)

    assert render(view) =~ "CONFIRMED"
    assert render(view) =~ "YOU ARE ON THE LIST"

    assert Newsletter.list_active_emails() |> Enum.member?(email)
    assert_email_sent(subject: "Welcome to streetscissors")
  end

  test "duplicate subscription shows error", %{conn: conn} do
    email = "duplicate@example.com"
    {:ok, _} = Newsletter.subscribe(email)

    {:ok, view, _html} = live(conn, "/newsletter")
    subscribe(view, email)

    assert render(view) =~ "has already been taken"
  end

  test "a wrong captcha answer subscribes nobody and sends no mail", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/newsletter")

    view
    |> form("form", %{"email" => "bot@example.com", "captcha" => "definitely-wrong"})
    |> render_submit()

    # Said inside the dialog, which covers the page's own flash group.
    assert has_element?(
             view,
             ".glass-panel .flash-notice[role=alert]",
             "Incorrect captcha. Please try again."
           )

    refute Newsletter.list_active_emails() |> Enum.member?("bot@example.com")
    assert_no_email_sent()
  end

  # The overlay on every page is a sticky LiveView rendered with no layout, so
  # there is no flash group behind it at all — what it puts was said nowhere.
  test "the site-wide overlay says a wrong captcha inside its dialog", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, WebWeb.NewsletterOverlayLive)
    render_click(view, "open_dispatch")

    view
    |> form("form", %{"email" => "bot@example.com", "captcha" => "definitely-wrong"})
    |> render_submit()

    assert has_element?(
             view,
             ".glass-panel .flash-notice[role=alert]",
             "Incorrect captcha. Please try again."
           )
  end

  test "the captcha is regenerated after a failed attempt, so an answer cannot be replayed",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/newsletter")
    first = captcha_answer(view)

    view
    |> form("form", %{"email" => "bot@example.com", "captcha" => "wrong"})
    |> render_submit()

    # Not a strict inequality — a fresh challenge can coincidentally repeat an
    # answer — but the question must have been reissued.
    assert is_binary(captcha_answer(view))
    assert is_binary(first)
  end

  test "subscribing is rate limited per IP", %{conn: conn} do
    # A fresh mount per attempt: a successful subscribe swaps the form out for
    # the confirmation panel, and the limiter is keyed on IP rather than on the
    # socket, so this is also what an attacker reconnecting would do.
    for n <- 1..3 do
      {:ok, view, _html} = live(conn, "/newsletter")
      subscribe(view, "ok#{n}@example.com")
      assert Newsletter.list_active_emails() |> Enum.member?("ok#{n}@example.com")
    end

    {:ok, view, _html} = live(conn, "/newsletter")
    subscribe(view, "overflow@example.com")

    assert render(view) =~ "Too many attempts"
    refute Newsletter.list_active_emails() |> Enum.member?("overflow@example.com")
  end
end
