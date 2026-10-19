defmodule WebWeb.AdminNav do
  @moduledoc """
  `on_mount` hook that gives every admin LiveView what the rail needs: the
  current path, so the page you are on is marked (and the layout can tell which
  program it is in, see `program/1`), and the counts of what is waiting, so the
  rail can say so without anyone opening a page to find out.

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
  The rail, top to bottom, as groups. A group is one of the site's programs
  (the Darkroom, the Cutting room, the Writing desk, Training, Mail) or one of
  the two neutral places: the Studio (the overview) at the top and Settings at
  the foot. Each carries:

    * `:id` and `:program`, the key `program/1` answers with and the accent
      the group wears (`st-program--<program>` in `assets/css/admin/base.css`)
    * `:heading`, the label printed over its links (`nil` for the two neutral
      ones, whose single link is their own label)
    * `:links`, each with `:label`, `:path`, `:icon` and, where the badge is a
      count of what waits, `:count`, a key in `counts/0`
  """
  def sections do
    [
      %{
        id: :studio,
        program: :studio,
        heading: nil,
        links: [
          %{label: "Studio", path: ~p"/admin/dashboard", icon: "hero-home"}
        ]
      },
      %{
        id: :darkroom,
        program: :darkroom,
        heading: "Darkroom",
        links: [
          %{label: "Scanner", path: ~p"/admin/scanner", icon: "hero-film"},
          %{label: "Prints", path: ~p"/admin/darkroom", icon: "hero-photo"},
          %{label: "Taste", path: ~p"/admin/darkroom/taste", icon: "hero-squares-2x2"}
        ]
      },
      %{
        id: :cuts,
        program: :cuts,
        heading: "Cutting room",
        links: [
          %{label: "Cutting room", path: ~p"/admin/cuts", icon: "hero-scissors"},
          %{
            label: "Captain's Logs",
            path: ~p"/admin/logs",
            icon: "hero-microphone",
            count: :logs
          }
        ]
      },
      %{
        id: :writing,
        program: :writing,
        heading: "Writing",
        links: [
          %{label: "Blog", path: ~p"/admin/blog", icon: "hero-document-text"},
          %{label: "Keywords", path: ~p"/admin/keywords", icon: "hero-tag"},
          %{
            label: "Content health",
            path: ~p"/admin/health",
            icon: "hero-clipboard-document-check"
          }
        ]
      },
      %{
        id: :training,
        program: :training,
        heading: "Training",
        links: [
          %{label: "Fitness", path: ~p"/admin/fitness", icon: "hero-heart"},
          %{label: "Activities", path: ~p"/admin/rides", icon: "hero-map-pin"}
        ]
      },
      %{
        id: :mail,
        program: :mail,
        heading: "Mail",
        links: [
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
        ]
      },
      %{
        id: :settings,
        program: :settings,
        heading: nil,
        links: [
          %{label: "Settings", path: ~p"/admin/settings", icon: "hero-cog-6-tooth"}
        ]
      }
    ]
  end

  @doc """
  Which program a path belongs to: `:darkroom`, `:cuts`, `:writing`,
  `:training`, `:mail`, or the neutral `:studio` / `:settings`. It is the group
  of the rail link nearest the path (`/admin/darkroom/taste` is Taste's, not
  Prints'), and `:studio` for anything the rail does not name.
  """
  def program(path) when is_binary(path) do
    candidates =
      for group <- sections(),
          link <- group.links,
          path == link.path or String.starts_with?(path, link.path <> "/"),
          do: {String.length(link.path), group.program}

    case Enum.max_by(candidates, &elem(&1, 0), fn -> nil end) do
      {_length, program} -> program
      nil -> :studio
    end
  end

  def program(_path), do: :studio

  @doc """
  The class that sets the page's accent (`--st-accent`): `st-program--darkroom`
  and so on, put on `.adm-main` by the admin layout.
  """
  def program_class(path), do: "st-program--#{program(path)}"

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
