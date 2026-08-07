defmodule Web.Rides.LiveTracking do
  @moduledoc """
  State for the public live-ride page, backed by site settings (no schema).

  A Komoot Premium live-tracking session produces a private per-ride share
  link that dies when the ride ends. The admin pastes it here to "go live";
  `current/0` hides it again after the TTL so a forgotten link never shows
  a dead session. A future self-hosted live map only needs to change this
  module's internals.
  """

  alias Web.SiteSettings

  @topic "live_ride"
  @url_key "live_ride_url"
  @started_key "live_ride_started_at"
  @note_key "live_ride_note"
  @ttl_key "live_ride_ttl_hours"
  @default_ttl 14
  @ttl_range 1..48

  def subscribe do
    Phoenix.PubSub.subscribe(Web.PubSub, @topic)
  end

  @doc "Accepts only https links on komoot.com or a komoot.com subdomain."
  def valid_live_url?(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        host == "komoot.com" or String.ends_with?(host, ".komoot.com")

      _ ->
        false
    end
  end

  def valid_live_url?(_), do: false

  def start_live(url, note \\ "") do
    url = String.trim(to_string(url))

    if valid_live_url?(url) do
      {:ok, _} = SiteSettings.put_setting(@url_key, url)
      {:ok, _} = SiteSettings.put_setting(@started_key, DateTime.to_iso8601(DateTime.utc_now()))
      put_or_delete(@note_key, String.trim(to_string(note)))

      info = current()
      broadcast({:live_ride, :started, info})
      {:ok, info}
    else
      {:error, :invalid_url}
    end
  end

  def stop_live do
    SiteSettings.delete_setting(@url_key)
    SiteSettings.delete_setting(@started_key)
    SiteSettings.delete_setting(@note_key)
    broadcast({:live_ride, :ended})
    :ok
  end

  @doc "The active session, or nil when none is set or the TTL has passed."
  def current do
    with %{url: url} = info when url != "" <- raw(),
         :lt <- DateTime.compare(DateTime.utc_now(), info.expires_at) do
      info
    else
      _ -> nil
    end
  end

  @doc "Stored values without the expiry check — the admin panel shows expired sessions."
  def raw do
    url = SiteSettings.get_setting(@url_key, "")
    started_at = parse_started_at(SiteSettings.get_setting(@started_key, ""))

    %{
      url: url,
      note: SiteSettings.get_setting(@note_key, ""),
      started_at: started_at,
      expires_at: DateTime.add(started_at, ttl_hours() * 3600, :second)
    }
  end

  def ttl_hours do
    case Integer.parse(to_string(SiteSettings.get_setting(@ttl_key, ""))) do
      {hours, _} -> clamp_ttl(hours)
      :error -> @default_ttl
    end
  end

  def put_ttl_hours(hours) do
    hours =
      case Integer.parse(to_string(hours)) do
        {n, _} -> clamp_ttl(n)
        :error -> @default_ttl
      end

    {:ok, _} = SiteSettings.put_setting(@ttl_key, Integer.to_string(hours))
    hours
  end

  # put_setting rejects blank values, so blank means delete.
  defp put_or_delete(key, ""), do: SiteSettings.delete_setting(key)
  defp put_or_delete(key, value), do: {:ok, _} = SiteSettings.put_setting(key, value)

  # A live link with a garbled timestamp should expire eventually, not crash.
  defp parse_started_at(value) do
    case DateTime.from_iso8601(to_string(value)) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp clamp_ttl(hours), do: hours |> max(@ttl_range.first) |> min(@ttl_range.last)

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Web.PubSub, @topic, message)
  end
end
