defmodule WebWeb.Visitor do
  @moduledoc """
  The one place a visitor is read off a request or a socket: their address,
  and whether what they did counts. Every hit, view and rate limit goes
  through here, so they all agree on who someone is and who is left out.

  **The address.** Caddy fronts the app on loopback, so the peer is always
  the proxy and the client is the first entry of `x-forwarded-for`. That
  header is believed only when the peer *is* loopback: were the port ever
  bound wider, a caller on the LAN could otherwise name any address it liked
  and slip every per-address limit. Getting this wrong fails quietly: until
  2026-09-22 log views recorded Caddy's `::1` for everyone, and per-address
  limits become one global bucket.

  LiveView sockets carry the address only because `endpoint.ex` declares
  `:peer_data`, `:x_headers` and `:user_agent` in `connect_info`, which is
  readable during `mount/3` alone. A LiveView nested with `live_render`
  cannot read it at all, so its host passes `"remote_ip"` in the session.

  **What counts** (`counted?/3`): not a bot by its user agent
  (`Web.Analytics.bot_user_agent?/1`), not the author's own reading
  (`WebWeb.OwnerMark`, and his addresses by hash in `Web.Analytics.Owner`),
  not an address in `EXCLUDED_IPS` or loopback. Page hits add their own path rules
  (`WebWeb.Plugs.Analytics`); log views use these as they are.

  Only `Web.Analytics.hash_ip/1` of an address is ever stored.
  """

  @loopback ["127.0.0.1", "::1"]

  @doc "The client's address for a conn or a LiveView socket, or `\"unknown\"`."
  def ip(%Plug.Conn{} = conn) do
    forwarded =
      if loopback?(conn.remote_ip) do
        conn |> Plug.Conn.get_req_header("x-forwarded-for") |> List.first() |> first_hop()
      end

    forwarded || format(conn.remote_ip) || "unknown"
  end

  def ip(%Phoenix.LiveView.Socket{} = socket) do
    peer =
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: address} -> address
        _ -> nil
      end

    forwarded = if peer == nil or loopback?(peer), do: forwarded_from_socket(socket)
    forwarded || format(peer) || "unknown"
  end

  @doc "The client's user agent for a conn or a LiveView socket (mount only), or nil."
  def user_agent(%Plug.Conn{} = conn),
    do: conn |> Plug.Conn.get_req_header("user-agent") |> List.first()

  def user_agent(%Phoenix.LiveView.Socket{} = socket) do
    case Phoenix.LiveView.get_connect_info(socket, :user_agent) do
      ua when is_binary(ua) -> ua
      _ -> nil
    end
  end

  @doc """
  Whether a visit by `ip` with `user_agent` counts: not a bot, not the admin
  (`admin?`), not an excluded or loopback address.
  """
  def counted?(ip, user_agent, mine?) do
    not mine? and not Web.Analytics.bot_user_agent?(user_agent) and not excluded?(ip)
  end

  import Bitwise

  @doc "Whether an address is the machine itself or one named in `EXCLUDED_IPS`."
  def excluded?(nil), do: false

  def excluded?(ip) when is_binary(ip) do
    cond do
      ip in @loopback ->
        true

      # The author's own addresses, by hash, gathered from his marker cookie,
      # the access log and the house's address (Web.Analytics.Owner). Checked
      # here rather than in counted?/3 so log views and rate limits inherit it.
      Web.Analytics.Owner.mine_ip?(ip) ->
        true

      true ->
        Enum.any?(excluded_list(), &matches_excluded?(&1, ip))
    end
  end

  def excluded?(_), do: false

  defp excluded_list do
    (System.get_env("EXCLUDED_IPS") || "")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp matches_excluded?(pattern, ip) do
    cond do
      pattern == ip ->
        true

      String.ends_with?(pattern, "*") ->
        String.starts_with?(ip, String.trim_trailing(pattern, "*"))

      String.contains?(pattern, "/") ->
        match_cidr?(pattern, ip)

      true ->
        false
    end
  end

  defp match_cidr?(cidr, ip) do
    with [net, bits_str] <- String.split(cidr, "/", parts: 2),
         {bits, ""} <- Integer.parse(bits_str),
         {:ok, net_ip} <- parse_ip(net),
         {:ok, client_ip} <- parse_ip(ip) do
      cidr_matches?(net_ip, client_ip, bits)
    else
      _ -> false
    end
  end

  defp parse_ip(str) do
    case :inet.parse_address(String.to_charlist(str)) do
      {:ok, ip} -> {:ok, ip}
      _ -> :error
    end
  end

  defp cidr_matches?({a, b, c, d}, {w, x, y, z}, bits) when bits in 0..32 do
    <<n::32>> = <<a, b, c, d>>
    <<cl::32>> = <<w, x, y, z>>
    shift = 32 - bits
    bsr(n, shift) == bsr(cl, shift)
  end

  defp cidr_matches?(_, _, _), do: false

  defp forwarded_from_socket(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :x_headers) do
      headers when is_list(headers) ->
        Enum.find_value(headers, fn {key, value} ->
          if String.downcase(key) == "x-forwarded-for", do: first_hop(value)
        end)

      _ ->
        nil
    end
  end

  # x-forwarded-for is a comma-separated chain; the client is the first hop.
  defp first_hop(nil), do: nil

  defp first_hop(value) do
    case value |> String.split(",") |> List.first() |> to_string() |> String.trim() do
      "" -> nil
      ip -> ip
    end
  end

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?({0, 0, 0, 0, 0, 65535, 32512, _}), do: true
  defp loopback?(_), do: false

  defp format(address) when is_tuple(address), do: address |> :inet.ntoa() |> to_string()
  defp format(_), do: nil
end
