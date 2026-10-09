defmodule WebWeb.FreshAssetsTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias WebWeb.FreshAssets

  # The suite serves undigested files, so there is no deploy to be behind.
  # This endpoint has had one: its stylesheet is now app-2222.css.
  defmodule Deployed do
    def config(:cache_static_manifest_latest),
      do: %{"assets/css/app.css" => "assets/css/app-2222.css"}
  end

  # A connected browser says which digested files its page was built with
  # (`phx-track-static` in the root layout).
  defp tab(holding, overrides \\ []) do
    struct(
      %Socket{
        endpoint: Deployed,
        router: WebWeb.Router,
        transport_pid: self(),
        private: %{connect_params: %{"_track_static" => holding}, live_temp: %{}}
      },
      overrides
    )
  end

  defp mount(socket) do
    assert {:cont, socket} = FreshAssets.on_mount(:default, %{}, %{}, socket)
    socket
  end

  defp told_to_reload?(socket), do: inspect(socket.private) =~ "stale-assets"

  test "a tab holding a stylesheet from before the deploy is told to load the page again" do
    assert ["http://localhost/assets/css/app-1111.css?vsn=d"]
           |> tab()
           |> mount()
           |> told_to_reload?()
  end

  test "a tab on the files now served is left alone" do
    refute ["http://localhost/assets/css/app-2222.css?vsn=d"]
           |> tab()
           |> mount()
           |> told_to_reload?()
  end

  test "nothing is said on the first, unconnected render" do
    stale = ["http://localhost/assets/css/app-1111.css?vsn=d"]
    refute stale |> tab(transport_pid: nil) |> mount() |> told_to_reload?()
  end

  # The root layout's sticky overlay inherits the session's hooks.
  test "a view the router did not mount is skipped" do
    stale = ["http://localhost/assets/css/app-1111.css?vsn=d"]
    refute stale |> tab(router: nil) |> mount() |> told_to_reload?()
  end

  test "the public pages run it, and the admin does not" do
    assert {WebWeb.FreshAssets, :default} in on_mount_of("/fitness/wiki/push-ups")
    refute {WebWeb.FreshAssets, :default} in on_mount_of("/admin/dashboard")
  end

  defp on_mount_of(path) do
    %{phoenix_live_view: {_view, _action, _opts, %{extra: extra}}} =
      Phoenix.Router.route_info(WebWeb.Router, "GET", path, "localhost")

    for %{id: id} <- Map.get(extra, :on_mount, []), do: id
  end
end
