defmodule WebWeb.AdminLive.Settings do
  @moduledoc """
  The few values the site reads from `site_settings` rather than from code or
  `.env`: things that change often enough that a redeploy would be silly.
  Each is its own small form, so saving one never resubmits another.

  Secrets stay in `.env`; nothing here should be private.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Notify
  alias Web.SiteSettings

  @default_playlist "37i9dQZF1DXcBWIGoYBM5M"
  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok,
       assign(socket,
         page_title: "Settings | Admin",
         spotify_playlist_id: SiteSettings.get_setting("spotify_playlist_id", @default_playlist),
         newsletter_test_email: SiteSettings.get_setting("newsletter_test_email", ""),
         notify_email: Notify.address() || "",
         portraits: Web.Author.portraits(),
         site_description: SiteSettings.get_setting("site_description", "")
       )
       # No limit to how many pictures are kept; a hundred is only how many
       # may be sent in one go. HEIC is left out on purpose: this machine's
       # ImageMagick cannot read it, and a phone asked for JPEG converts its
       # own pictures before sending them.
       |> allow_upload(:portrait,
         accept: ~w(.jpg .jpeg .png .webp),
         max_entries: 100,
         max_file_size: 80_000_000,
         auto_upload: true,
         progress: &portrait_progress/3
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

    if email != "" and not String.match?(email, @email) do
      {:noreply, put_flash(socket, :error, "That doesn't look like an email address.")}
    else
      # A setting cannot hold an empty value, so clearing one is deleting it.
      if email == "",
        do: SiteSettings.delete_setting("newsletter_test_email"),
        else: {:ok, _} = SiteSettings.put_setting("newsletter_test_email", email)

      message = if email == "", do: "Test address cleared.", else: "Test sends go to #{email}."

      {:noreply,
       socket
       |> assign(newsletter_test_email: email)
       |> put_flash(:info, message)}
    end
  end

  def handle_event("save_notify_email", %{"notify_email" => raw}, socket) do
    email = String.trim(raw)

    if email != "" and not String.match?(email, @email) do
      {:noreply, put_flash(socket, :error, "That doesn't look like an email address.")}
    else
      Notify.put_address(email)

      # Clearing the setting falls back to NOTIFY_EMAIL when that is set, so
      # the field shows what is actually in force rather than an empty box.
      message =
        case Notify.address() do
          nil -> "Alerts have nowhere to go until an address is set."
          address -> "Alerts go to #{address}."
        end

      {:noreply,
       socket |> assign(notify_email: Notify.address() || "") |> put_flash(:info, message)}
    end
  end

  def handle_event("save_site_description", %{"site_description" => raw}, socket) do
    said = String.trim(raw)

    # A setting cannot hold an empty value, so clearing one is deleting it.
    if said == "",
      do: SiteSettings.delete_setting("site_description"),
      else: {:ok, _} = SiteSettings.put_setting("site_description", said)

    message = if said == "", do: "The homepage says nothing about itself.", else: "Saved."
    {:noreply, socket |> assign(site_description: said) |> put_flash(:info, message)}
  end

  def handle_event("portrait_change", _params, socket), do: {:noreply, socket}

  def handle_event("remove_portrait", %{"path" => path}, socket) do
    Web.Author.remove_portrait(path)

    {:noreply,
     socket
     |> assign(portraits: Web.Author.portraits())
     |> put_flash(:info, "Picture removed.")}
  end

  def handle_event("test_notify", _params, socket) do
    result =
      Notify.deliver(
        "streetscissors: a test from the settings page",
        "This is the address the site writes to when a signature is waiting or something on the machine has failed.\n\nNothing is wrong. You asked for this one."
      )

    case result do
      {:ok, _job} -> {:noreply, put_flash(socket, :info, "Test queued to #{Notify.address()}.")}
      _ -> {:noreply, put_flash(socket, :error, "Set an address first.")}
    end
  end

  defp portrait_progress(:portrait, entry, socket) do
    if entry.done? do
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Web.Author.add_portrait(path)}
        end)

      socket = assign(socket, portraits: Web.Author.portraits())

      case result do
        {:ok, _path} -> {:noreply, socket}
        {:error, why} -> {:noreply, put_flash(socket, :error, "#{entry.client_name}: #{why}")}
      end
    else
      {:noreply, socket}
    end
  end

  defp portrait_error(:too_large), do: "That file is over 80 MB."
  defp portrait_error(:not_accepted), do: "Pictures only: JPEG, PNG or WebP."
  defp portrait_error(:too_many_files), do: "A hundred at a time; send the rest in a second go."
  defp portrait_error(other), do: "Upload failed (#{inspect(other)})."

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

    <.panel title="About page pictures">
      <form id="settings-portraits" phx-change="portrait_change" class="adm-sheet">
        <.drop_zone
          upload={@uploads.portrait}
          title="Add pictures of yourself"
          hint="As many as you like. The About page shows a different one each time it loads, with the rest in a small gallery under it."
          browse="Choose pictures"
          error_message={&portrait_error/1}
        />
      </form>
      <p :if={@portraits == []} class="adm-help">None yet: the About page shows no picture.</p>
      <div :if={@portraits != []} class="adm-images" id="settings-portrait-list">
        <div
          :for={path <- @portraits}
          class="adm-image"
          id={"portrait-" <> Path.basename(path, ".jpg")}
        >
          <img src={path} alt="" loading="lazy" />
          <div class="adm-image-body">
            <button
              type="button"
              class="adm-btn adm-btn--quiet adm-btn--small"
              phx-click="remove_portrait"
              phx-value-path={path}
              data-confirm="Remove this picture from the About page?"
            >
              Remove
            </button>
          </div>
        </div>
      </div>
    </.panel>

    <.panel title="Homepage sentence">
      <form phx-submit="save_site_description" id="settings-description" class="adm-sheet">
        <label class="adm-label" for="site_description">What the site is, in a sentence</label>
        <div class="adm-inline-form">
          <input
            type="text"
            id="site_description"
            name="site_description"
            value={@site_description}
            class="adm-input"
            placeholder="Leave empty to say nothing"
            autocomplete="off"
          />
          <button type="submit" class="adm-btn">Save</button>
        </div>
        <p class="adm-help">
          Shown at the foot of the homepage, for a visitor who arrives knowing nothing.
        </p>
      </form>
    </.panel>

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

    <.panel title="Alerts">
      <form phx-submit="save_notify_email" id="settings-alerts" class="adm-sheet">
        <label class="adm-label" for="notify_email">Where the site writes to you</label>
        <div class="adm-inline-form">
          <input
            type="email"
            id="notify_email"
            name="notify_email"
            value={@notify_email}
            class="adm-input"
            placeholder="you@example.com"
            autocomplete="email"
          />
          <button type="submit" class="adm-btn">Save</button>
          <button
            :if={@notify_email != ""}
            type="button"
            phx-click="test_notify"
            id="settings-alerts-test"
            class="adm-btn adm-btn--quiet"
          >
            Send a test
          </button>
        </div>
        <p class="adm-help">
          A guestbook signature waiting for approval, and anything on the machine that has failed:
          the certificate, the proxy, the domain's address, the disk, a backup. A fault is mailed
          once, again each day it lasts, and once more when it clears.
        </p>
      </form>
    </.panel>
    """
  end
end
