defmodule WebWeb.AdminLive.Settings do
  @moduledoc """
  The few values the site reads from `site_settings` rather than from code or
  `.env`: things that change often enough that a redeploy would be silly.
  Each is its own small form, so saving one never resubmits another.

  Secrets stay in `.env`; nothing here should be private.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.SiteSettings

  @default_playlist "37i9dQZF1DXcBWIGoYBM5M"

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok,
       assign(socket,
         page_title: "Settings | Admin",
         spotify_playlist_id: SiteSettings.get_setting("spotify_playlist_id", @default_playlist),
         newsletter_test_email: SiteSettings.get_setting("newsletter_test_email", "")
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_event("save_settings", %{"spotify_playlist_id" => raw_input}, socket) do
    playlist_id = playlist_id(raw_input)

    case SiteSettings.put_setting("spotify_playlist_id", playlist_id) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> assign(spotify_playlist_id: playlist_id)
         |> put_flash(:info, "Playlist saved: #{playlist_id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save the playlist.")}
    end
  end

  def handle_event("save_test_email", %{"newsletter_test_email" => raw}, socket) do
    email = String.trim(raw)

    if email != "" and not String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/) do
      {:noreply, put_flash(socket, :error, "That doesn't look like an email address.")}
    else
      {:ok, _} = SiteSettings.put_setting("newsletter_test_email", email)

      message = if email == "", do: "Test address cleared.", else: "Test sends go to #{email}."

      {:noreply,
       socket
       |> assign(newsletter_test_email: email)
       |> put_flash(:info, message)}
    end
  end

  # A pasted share link (open.spotify.com/playlist/<id>?si=…) or the bare id.
  defp playlist_id(input) do
    input = String.trim(input)

    case Regex.run(~r{playlist/([a-zA-Z0-9]+)}, input) do
      [_, id] -> id
      nil -> input
    end
  end

  def render(assigns) do
    ~H"""
    <.page_head slug="Settings" title="Settings">
      <:lede>
        Values the site reads on every request. Saving one takes effect on the next page load.
      </:lede>
    </.page_head>

    <.panel title="Homepage player">
      <form phx-submit="save_settings" id="settings-spotify" class="adm-sheet">
        <label class="adm-label" for="spotify_playlist_id">Spotify playlist</label>
        <div class="adm-inline-form">
          <input
            type="text"
            id="spotify_playlist_id"
            name="spotify_playlist_id"
            value={@spotify_playlist_id}
            class="adm-input"
            placeholder="Paste a playlist link or its ID"
            autocomplete="off"
          />
          <button type="submit" class="adm-btn">Save</button>
        </div>
        <p class="adm-help">
          The player in the homepage's corner. A full share link works; the ID is taken out of it.
        </p>
      </form>
    </.panel>

    <.panel title="Newsletter">
      <form phx-submit="save_test_email" id="settings-newsletter" class="adm-sheet">
        <label class="adm-label" for="newsletter_test_email">Test-send address</label>
        <div class="adm-inline-form">
          <input
            type="email"
            id="newsletter_test_email"
            name="newsletter_test_email"
            value={@newsletter_test_email}
            class="adm-input"
            placeholder="you@example.com"
            autocomplete="email"
          />
          <button type="submit" class="adm-btn">Save</button>
        </div>
        <p class="adm-help">
          Where the newsletter's "Send a test" goes by default. It can still be changed per send.
        </p>
      </form>
    </.panel>
    """
  end
end
