defmodule WebWeb.BiometricsLiveTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest

  # These notices were always in the HTML — printed as bare text under the
  # webhook section, outside the steel wrapper, where nobody saw them — so
  # each test checks for the styled notice, not just the words.

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => true})

  # mount/3 uses a plain redirect, so following it yields a conn, not a view.
  test "a visitor is sent to the regimen and told why", %{conn: conn} do
    {:ok, conn} =
      conn
      |> live(~p"/fitness/biometrics")
      |> follow_redirect(conn, ~p"/fitness")

    {:ok, view, _html} = live(conn)

    assert has_element?(view, "#flash-error.flash-notice[role=alert]", "Administrators only.")
  end

  test "a recorded entry is confirmed in a notice that can be dismissed", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/fitness/biometrics")

    view
    |> form("form.bio-form", biometric: %{date: "2026-09-14", hrv_ms: "55"})
    |> render_submit()

    assert has_element?(view, "#flash-info.flash-notice[role=status]", "Entry recorded.")

    view |> element("#flash-info button.flash-notice-close") |> render_click()

    refute has_element?(view, "#flash-info")
  end

  test "saving a webhook token is confirmed in a notice", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/fitness/biometrics")

    view
    |> form("form.bio-webhook-custom", token: "an-invented-token")
    |> render_submit()

    assert has_element?(view, "#flash-info.flash-notice[role=status]", "Webhook token saved.")
  end
end
