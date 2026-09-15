defmodule WebWeb.ClientIP do
  @moduledoc """
  Resolves the real client IP behind the reverse proxy.

  Caddy fronts this app on localhost, so `peer_data`/`remote_ip` is always
  `127.0.0.1` — the actual client is the first entry of `x-forwarded-for`.
  Getting this wrong silently defeats anything keyed on the client: the audio
  play tracker still records a constant `127.0.0.1` for exactly this reason,
  and per-IP rate limits would degrade into one global bucket.

  LiveView sockets only carry these when the socket declares them in
  `connect_info` — `endpoint.ex` lists `:peer_data` and `:x_headers`.
  """

  @doc "Client IP for a LiveView socket, or `\"unknown\"`."
  def from_socket(socket) do
    forwarded_from_socket(socket) || peer_from_socket(socket) || "unknown"
  end

  @doc "Client IP for a Plug.Conn, or `\"unknown\"`."
  def from_conn(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [value | _] -> first_forwarded(value)
      [] -> format(conn.remote_ip)
    end || "unknown"
  end

  defp forwarded_from_socket(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :x_headers) do
      headers when is_list(headers) ->
        Enum.find_value(headers, fn {key, value} ->
          if String.downcase(key) == "x-forwarded-for", do: first_forwarded(value)
        end)

      _ ->
        nil
    end
  end

  defp peer_from_socket(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> format(address)
      _ -> nil
    end
  end

  # x-forwarded-for is a comma-separated chain; the client is the first hop.
  defp first_forwarded(value) do
    case value |> String.split(",") |> List.first() |> to_string() |> String.trim() do
      "" -> nil
      ip -> ip
    end
  end

  defp format(address) when is_tuple(address), do: address |> :inet.ntoa() |> to_string()
  defp format(_), do: nil
end
