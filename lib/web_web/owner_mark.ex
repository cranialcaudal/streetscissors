defmodule WebWeb.OwnerMark do
  @moduledoc """
  Marks a browser as the author's, so its reading is not counted.

  `Web.Analytics.Owner` explains why an address cannot carry this. A browser
  can: it is the one thing that stays the same when the home address
  changes, when the provider changes, and when a phone leaves through iCloud
  Private Relay from a different Fastly address every day.

  The mark is set on any request made with an admin session and **slid forward
  on every request that already has it**, which is the part that is easy to
  get wrong: browsers cap a cookie's life at around thirteen months whatever
  `max_age` asks for, so the long window below is how long a mark is believed,
  not how long one lasts untouched. Reading the site at any point in a year
  keeps it.

  **Logging out does not clear it.** Logging out says "stop showing me the
  admin", not "start counting me". Only `forget/1` clears it, from the button
  on `/admin/readers`.

  The mark is signed so it cannot be typed out by hand, but it is **not a
  credential**: it grants nothing, and all a forged one buys is being left out
  of a figure on a page only the author can see. Nothing should ever come to
  depend on it for access.

  A LiveView cannot read cookies — `connect_info` carries the peer, the
  forwarded headers and the user agent, and nothing else — so the plug mirrors
  the mark into the session, and `mine?/1` accepts either a conn or a mounting
  LiveView's session map.
  """

  import Plug.Conn

  @cookie "_ss_mine"
  @salt "owner marker v1"
  @max_age 10 * 365 * 24 * 60 * 60

  @doc "The cookie's name, for the one place that has to delete it."
  def cookie, do: @cookie

  @doc """
  Whether this request or this mounting LiveView belongs to the author.

  Takes a conn, or the session map a LiveView is mounted with. The admin flag
  is read as truthy rather than `== true`: `init_test_session/2` stores the
  string `"true"`, and a rule that counts the author in the suite but not on
  the site is worse than no rule.
  """
  def mine?(%Plug.Conn{} = conn) do
    admin_session?(conn) or marked_session?(conn) or marked_cookie?(conn)
  end

  def mine?(%{} = session) do
    truthy?(session["admin_user"]) or truthy?(session["owner"])
  end

  def mine?(_), do: false

  @doc "Marks this browser as the author's, and mirrors it into the session."
  def mark(%Plug.Conn{} = conn) do
    token = Phoenix.Token.sign(WebWeb.Endpoint, @salt, %{at: System.os_time(:second)})

    conn
    |> put_resp_cookie(@cookie, token,
      max_age: @max_age,
      http_only: true,
      same_site: "Lax",
      secure: Application.get_env(:web, :secure_cookies?, false)
    )
    |> put_session("owner", true)
  end

  @doc "Unmarks this browser, so it is counted like anyone else."
  def forget(%Plug.Conn{} = conn) do
    conn
    |> delete_resp_cookie(@cookie)
    |> delete_session("owner")
  end

  defp admin_session?(conn) do
    truthy?(get_session(conn, "admin_user"))
  rescue
    # No session fetched (a no-pipeline route): there is nothing to read.
    _ -> false
  end

  defp marked_session?(conn) do
    truthy?(get_session(conn, "owner"))
  rescue
    _ -> false
  end

  defp marked_cookie?(conn) do
    conn = fetch_cookies(conn)

    case conn.cookies[@cookie] do
      token when is_binary(token) ->
        match?({:ok, _}, Phoenix.Token.verify(WebWeb.Endpoint, @salt, token, max_age: @max_age))

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false
end
