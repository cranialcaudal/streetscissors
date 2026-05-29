defmodule WebWeb.NewsletterLiveTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Web.Newsletter

  test "user can subscribe and receive welcome email", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/newsletter")

    email = "test@example.com"

    view
    |> form("form", %{"email" => email})
    |> render_submit()

    # Check for success message
    assert render(view) =~ "CONFIRMED"
    assert render(view) =~ "YOU ARE ON THE LIST"

    # Verify DB
    assert Newsletter.list_active_emails() |> Enum.member?(email)

    # Verify Email (Swoosh Local Adapter)
    assert_email_sent(subject: "Welcome to streetscissors")
  end

  test "duplicate subscription shows error", %{conn: conn} do
    email = "duplicate@example.com"
    {:ok, _} = Newsletter.subscribe(email)

    {:ok, view, _html} = live(conn, "/newsletter")

    view
    |> form("form", %{"email" => email})
    |> render_submit()

    assert render(view) =~ "has already been taken"
  end
end
