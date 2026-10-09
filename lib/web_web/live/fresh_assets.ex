defmodule WebWeb.FreshAssets do
  @moduledoc """
  Reloads a page that is running on a stylesheet or script from before a
  deploy.

  A tab left open across `./redeploy.sh` reconnects to the new release and is
  sent the new markup, but its `<head>` still names the old digested
  `app.css`, so anything the deploy added arrives unstyled. The root layout
  marks both files `phx-track-static`; this is the other half, which asks on
  each connected mount whether they have moved and, if so, tells the browser
  to load the page again (`phx:stale-assets` in app.js, which will not do it
  twice in a row or while something is being typed).

  Only the public `live_session`: a reload in the admin could cost a
  recording in the booth. Views the router didn't mount are skipped, since
  the root layout's sticky overlay inherits the session's hooks.
  """
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, %{router: nil} = socket), do: {:cont, socket}

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) and static_changed?(socket) do
      {:cont, push_event(socket, "stale-assets", %{})}
    else
      {:cont, socket}
    end
  end
end
