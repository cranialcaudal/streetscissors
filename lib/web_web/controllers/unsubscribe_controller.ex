defmodule WebWeb.UnsubscribeController do
  use WebWeb, :controller

  alias Web.Newsletter
  alias WebWeb.Unsubscribe

  @moduledoc """
  Unsubscribing from the newsletter.

  Three entry points, because mail clients and humans arrive differently:

    * `show`      — GET from the footer link. Explains and asks for one click.
    * `update`    — POST from that page's form.
    * `one_click` — POST from a mail client honouring RFC 8058, with no session
                    and no CSRF token. Exempt from `protect_from_forgery` in the
                    router; the signed token in the URL is what authenticates it,
                    and the action is idempotent and harmless.

  A bad token is never distinguished from an address that was not subscribed:
  this endpoint must not be usable to find out who is on the list.
  """

  def show(conn, %{"token" => token}) do
    case Unsubscribe.verify(token) do
      {:ok, subscriber} ->
        render(conn, :show, email: subscriber.email, token: token, page_title: "Unsubscribe")

      :error ->
        conn
        |> put_status(:not_found)
        |> render(:invalid, page_title: "Unsubscribe")
    end
  end

  def update(conn, %{"token" => token}) do
    case Unsubscribe.verify(token) do
      {:ok, subscriber} ->
        Newsletter.unsubscribe(subscriber.email)
        render(conn, :done, email: subscriber.email, page_title: "Unsubscribed")

      :error ->
        conn
        |> put_status(:not_found)
        |> render(:invalid, page_title: "Unsubscribe")
    end
  end

  # Mail clients expect 200 and no body. They are not going to read a page.
  def one_click(conn, %{"token" => token}) do
    case Unsubscribe.verify(token) do
      {:ok, subscriber} ->
        Newsletter.unsubscribe(subscriber.email)
        send_resp(conn, 200, "")

      :error ->
        send_resp(conn, 404, "")
    end
  end
end
