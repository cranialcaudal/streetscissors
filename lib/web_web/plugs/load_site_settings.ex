defmodule WebWeb.Plugs.LoadSiteSettings do
  @moduledoc """
  Loads global site settings into connection assigns.
  """
  import Plug.Conn
  alias Web.SiteSettings

  def init(opts), do: opts

  def call(conn, _opts) do
    # 37i9dQZF1DXcBWIGoYBM5M is the default "Today's Top Hits" playlist
    playlist_id = SiteSettings.get_setting("spotify_playlist_id", "37i9dQZF1DXcBWIGoYBM5M")

    conn
    |> assign(:spotify_playlist_id, playlist_id)
  end
end
