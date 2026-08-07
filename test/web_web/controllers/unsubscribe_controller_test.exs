defmodule WebWeb.UnsubscribeControllerTest do
  use WebWeb.ConnCase

  alias Web.Newsletter
  alias WebWeb.Unsubscribe

  setup do
    Web.RateLimit.reset_all()
    {:ok, subscriber} = Newsletter.subscribe("reader@example.com")
    {:ok, subscriber: subscriber, token: subscriber.unsubscribe_token}
  end

  describe "the confirm page" do
    test "shows the address and asks for one click", %{conn: conn, token: token} do
      html = conn |> get(~p"/unsubscribe/#{token}") |> html_response(200)

      assert html =~ "reader@example.com"
      assert html =~ "Unsubscribe"
    end

    test "GET does not unsubscribe — scanners and mail clients prefetch links",
         %{conn: conn, token: token} do
      get(conn, ~p"/unsubscribe/#{token}")

      assert Newsletter.subscribed?("reader@example.com")
    end

    test "a garbage token 404s without saying whether the address exists", %{conn: conn} do
      html = conn |> get(~p"/unsubscribe/not-a-real-token") |> html_response(404)

      assert html =~ "didn't work"
      refute html =~ "@example.com"
    end
  end

  describe "unsubscribing" do
    test "POST removes the address from the sending list", %{conn: conn, token: token} do
      assert Newsletter.subscribed?("reader@example.com")

      html = conn |> post(~p"/unsubscribe/#{token}") |> html_response(200)

      assert html =~ "Unsubscribed"
      refute Newsletter.subscribed?("reader@example.com")
      refute "reader@example.com" in Newsletter.list_active_emails()
    end

    test "keeps a suppression record rather than deleting the row", %{conn: conn, token: token} do
      post(conn, ~p"/unsubscribe/#{token}")

      # Deleting would let the same address be re-added and mailed again, which
      # is the thing an unsubscribe is supposed to prevent.
      subscriber = Enum.find(Newsletter.list_subscribers(), &(&1.email == "reader@example.com"))
      assert subscriber
      refute subscriber.active
    end

    test "is idempotent", %{conn: conn, token: token} do
      post(conn, ~p"/unsubscribe/#{token}")
      assert conn |> post(~p"/unsubscribe/#{token}") |> html_response(200) =~ "Unsubscribed"
      refute Newsletter.subscribed?("reader@example.com")
    end

    test "a token for nobody is an invalid link, not a silent success", %{conn: conn} do
      assert Unsubscribe.token("stranger@example.com") == nil
      assert conn |> post(~p"/unsubscribe/nosuchtoken") |> html_response(404) =~ "didn\'t work"
    end
  end

  describe "RFC 8058 one-click" do
    test "POSTs with no session or CSRF token and returns an empty 200", %{token: token} do
      # Deliberately a bare conn: this arrives from a mail provider, not a
      # browser with a session.
      conn = post(build_conn(), ~p"/unsubscribe/#{token}/one-click")

      assert response(conn, 200) == ""
      refute Newsletter.subscribed?("reader@example.com")
    end

    test "a bad token 404s", %{} do
      conn = post(build_conn(), ~p"/unsubscribe/nonsense/one-click")
      assert response(conn, 404) == ""
    end
  end

  describe "tokens" do
    test "resolve to their subscriber, and reject tampering", %{token: token} do
      assert {:ok, subscriber} = Unsubscribe.verify(token)
      assert subscriber.email == "reader@example.com"

      assert Unsubscribe.verify(token <> "x") == :error
      assert Unsubscribe.verify("") == :error
      assert Unsubscribe.verify(nil) == :error
    end

    test "do not leak the address they belong to", %{token: token} do
      # Or the endpoint becomes a way to unsubscribe anyone by editing a URL.
      refute token =~ "reader"
      refute token =~ "example.com"
    end

    test "are stable, so a link in an old email keeps working", %{token: token} do
      # The whole reason these are stored rather than signed with
      # secret_key_base: rotating that secret must not break sent links.
      assert Unsubscribe.token("reader@example.com") == token

      {:ok, _} = Newsletter.unsubscribe("reader@example.com")
      assert Unsubscribe.token("reader@example.com") == token
    end

    test "are unique per subscriber" do
      {:ok, other} = Newsletter.subscribe("second@example.com")
      assert other.unsubscribe_token
      refute other.unsubscribe_token == Unsubscribe.token("reader@example.com")
    end
  end

  describe "resubscribing" do
    test "someone who unsubscribed can come back", %{conn: conn, token: token} do
      post(conn, ~p"/unsubscribe/#{token}")
      refute Newsletter.subscribed?("reader@example.com")

      # A plain insert would fail the unique constraint and tell a returning
      # reader their address "has already been taken".
      assert {:ok, _} = Newsletter.subscribe("reader@example.com")
      assert Newsletter.subscribed?("reader@example.com")
    end

    test "subscribing twice while active still reports the duplicate" do
      assert {:error, changeset} = Newsletter.subscribe("reader@example.com")
      assert "has already been taken" in Web.DataCase.errors_on(changeset).email
    end
  end
end
