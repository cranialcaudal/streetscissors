defmodule WebWeb.AdminNav do
  @moduledoc """
  `on_mount` hook that gives every admin LiveView what the rail needs: the
  current path, so the page you are on is marked, and the counts of what is
  waiting, so the rail can say so without anyone opening a page to find out.

  It runs after `WebWeb.AdminAuth`, so nothing here is computed for a visitor
  who is about to be redirected away. The counts are read once per mount —
  every admin navigation is a mount — and a handler that changes one (an
  approval, an archived message) calls `refresh_counts/1` so the badge keeps
  up with the page rather than waiting for the next navigation.
  """

  use WebWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  @doc """
  The rail, top to bottom. Groups follow what the work is — writing, mail,
  syncing — rather than the order the pages were built in. `count` names a
  key in `counts/0` whose badge the link carries.
  """
  def sections do
    [
      {nil,
       [
         %{label: "Overview", path: ~p"/admin/dashboard", icon: "hero-home"}
       ]},
      {"Write",
       [
         %{label: "Blog", path: ~p"/admin/blog", icon: "hero-document-text"},
         %{label: "Captain's Logs", path: ~p"/admin/logs", icon: "hero-microphone", count: :logs},
         %{label: "Fitness", path: ~p"/admin/fitness", icon: "hero-heart"}
       ]},
      {"Darkroom",
       [
         %{label: "Scanner", path: ~p"/admin/scanner", icon: "hero-film"}
       ]},
      {"Mail",
       [
         %{label: "Inbox", path: ~p"/admin/inbox", icon: "hero-inbox", count: :inbox},
         %{
           label: "Guestbook",
           path: ~p"/admin/guestbook",
           icon: "hero-book-open",
           count: :guestbook
         },
         %{
           label: "Citations",
           path: ~p"/admin/citations",
           icon: "hero-chat-bubble-left-right",
           count: :citations
         },
         %{label: "Newsletter", path: ~p"/admin/newsletter", icon: "hero-envelope"}
       ]},
      {"Sync",
       [
         %{label: "Activities", path: ~p"/admin/rides", icon: "hero-map-pin"}
       ]},
      {nil,
       [
         %{label: "Settings", path: ~p"/admin/settings", icon: "hero-cog-6-tooth"}
       ]}
    ]
  end

  # The root layout live_renders the newsletter overlay on every page, and a
  # nested view inherits the live_session's hooks. It has no rail and no URL
  # of its own (so no :handle_params to hook), and nothing here concerns it.
  def on_mount(:default, _params, _session, %{router: nil} = socket), do: {:cont, socket}

  def on_mount(:default, _params, _session, socket) do
    # `admin_chrome` tells the root layout the rail is already on screen, so
    # the public pages' floating "Admin" indicator stays off these pages.
    socket =
      socket
      |> assign(:admin_chrome, true)
      |> assign(:admin_path, nil)
      |> refresh_counts()
      |> attach_hook(:admin_path, :handle_params, fn _params, uri, socket ->
        {:cont, assign(socket, :admin_path, URI.parse(uri).path)}
      end)

    {:cont, socket}
  end

  @doc "Re-reads the badge counts into `@admin_counts`."
  def refresh_counts(socket), do: assign(socket, :admin_counts, counts())

  @doc """
  What is waiting, by rail key: open messages (inbox + needs attention, which
  includes letters), held guestbook signatures, verified citations awaiting
  approval, and logs whose transcode failed.
  """
  def counts do
    messages = Web.Contact.count_by_status()

    %{
      inbox: Map.get(messages, "inbox", 0) + Map.get(messages, "attention", 0),
      guestbook: Web.General.count_held_guestbook_entries(),
      citations: Web.Webmentions.count_held(),
      logs: Map.get(Web.Audio.count_by_status(), "failed", 0)
    }
  end
end
