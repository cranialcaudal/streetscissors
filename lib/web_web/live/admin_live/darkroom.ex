defmodule WebWeb.AdminLive.Darkroom do
  @moduledoc """
  The prints, roll by roll, to pick one to edit (`/admin/darkroom`).

  With no roll in the address the page is the shelf: the rolls that have prints,
  each as a card with its contact sheet, how many prints it has and how many are
  edited, over a short row of the prints edited last. `?roll=065` is one roll's
  prints on the dark bay, each marked when it is edited, repaired, or has a
  Stable Diffusion fill waiting to be looked at (`Web.Darkroom`,
  `Web.Darkroom.Repair`). Nothing here is slow: it is a directory listing per
  roll and a stat per edit.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Darkroom
  alias Web.Darkroom.Repair
  alias Web.Negatives

  # How many of the prints edited last are shown on the shelf.
  @recent 6

  def mount(_params, session, socket) do
    if session["admin_user"] do
      rolls =
        for sheet <- Enum.sort_by(Negatives.list_contact_sheets(), & &1.roll_num, :desc),
            prints = Negatives.list_frames(sheet.roll),
            prints != [],
            {:ok, dir} <- [Negatives.roll_dir(sheet.roll)] do
          edits = edits(dir)

          %{
            roll: sheet.roll,
            dir: dir,
            format: sheet.format,
            color: sheet.color,
            sheet: Negatives.sized_url(sheet.preview_url, 480),
            prints: length(prints),
            edited: Enum.count(prints, &Map.has_key?(edits, &1.frame)),
            recent: for(print <- prints, at = edits[print.frame], at, do: {print, at})
          }
        end

      {:ok,
       assign(socket,
         page_title: "Prints | Admin",
         rolls: rolls,
         recent: recent(rolls),
         sheets: Enum.sum(Enum.map(rolls, & &1.prints)),
         edited: Enum.sum(Enum.map(rolls, & &1.edited))
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_params(params, _uri, socket) do
    rolls = socket.assigns.rolls
    index = Enum.find_index(rolls, &(&1.roll == params["roll"]))
    roll = index && Enum.at(rolls, index)

    prints =
      if roll do
        for print <- Negatives.list_frames(roll.roll) do
          print
          |> Map.put(:edited, Darkroom.edited?(roll.dir, print.frame))
          |> Map.put(:repaired, Repair.repaired?(roll.dir, print.frame))
          |> Map.put(:candidate, Repair.candidate?(roll.dir, print.frame))
        end
      else
        []
      end

    {:noreply,
     assign(socket,
       roll: roll,
       prints: prints,
       newer: index && index > 0 && Enum.at(rolls, index - 1),
       older: index && Enum.at(rolls, index + 1)
     )}
  end

  # `%{frame => when it was last printed}` for a roll's edited prints, from the
  # recipes beside them.
  defp edits(dir) do
    case File.ls(Path.join(dir, "edits")) do
      {:ok, files} ->
        for file <- files,
            [_, digits] <- [Regex.run(~r/\A(\d+)\.json\z/, file)],
            {:ok, %File.Stat{mtime: mtime}} <-
              [File.stat(Path.join([dir, "edits", file]), time: :posix)],
            into: %{} do
          {String.to_integer(digits), DateTime.from_unix!(mtime)}
        end

      _ ->
        %{}
    end
  end

  # The prints edited last, across every roll, newest first.
  defp recent(rolls) do
    rolls
    |> Enum.flat_map(fn roll ->
      for {print, at} <- roll.recent, do: %{roll: roll.roll, print: print, at: at}
    end)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> Enum.take(@recent)
  end

  def render(assigns) do
    ~H"""
    <.page_head :if={!@roll} slug="Darkroom / Prints" title="Prints">
      <:lede>
        Pick a print to edit. An edit is kept beside the print as a recipe, and the print
        as it was developed is never lost: Revert puts it back.
      </:lede>
      <:actions>
        <.link navigate={~p"/admin/scanner"} class="adm-btn">
          <.icon name="hero-film" class="size-4" /> Scan a roll
        </.link>
      </:actions>
    </.page_head>

    <.page_head :if={@roll} slug="Darkroom / Prints" title={"Roll #{@roll.roll}"}>
      <:lede>
        {@roll.format}, {film(@roll.color)}. {count(@roll.prints, "print")}, {edited_line(
          @roll.edited
        )}.
      </:lede>
      <:actions>
        <.link patch={~p"/admin/darkroom"} class="adm-btn adm-btn--quiet">
          <.icon name="hero-arrow-left" class="size-4" /> All rolls
        </.link>
        <span class="adm-dr-neighbours" role="group" aria-label="Other rolls">
          <.link
            :if={@newer}
            patch={~p"/admin/darkroom?roll=#{@newer.roll}"}
            class="adm-btn adm-btn--quiet"
            aria-label={"Newer roll, #{@newer.roll}"}
          >
            <.icon name="hero-chevron-left" class="size-4" /> {@newer.roll}
          </.link>
          <.link
            :if={@older}
            patch={~p"/admin/darkroom?roll=#{@older.roll}"}
            class="adm-btn adm-btn--quiet"
            aria-label={"Older roll, #{@older.roll}"}
          >
            {@older.roll} <.icon name="hero-chevron-right" class="size-4" />
          </.link>
        </span>
        <.link href={~p"/negatives/roll/#{@roll.roll}"} target="_blank" class="adm-btn">
          <.icon name="hero-arrow-top-right-on-square" class="size-4" /> On /negatives
        </.link>
      </:actions>
    </.page_head>

    <%!-- No roll has a print: say what makes one. --%>
    <section :if={@rolls == []} class="adm-panel adm-dr-nothing">
      <.empty>
        <span>
          No roll has prints yet. A print is one frame, scanned at full size and developed: scan a roll
          first, tick the frames to keep, and they appear here.
        </span>
        <.link navigate={~p"/admin/scanner"} class="adm-btn adm-btn--primary">
          <.icon name="hero-film" class="size-4" /> Open the scanner
        </.link>
      </.empty>
    </section>

    <%!-- The shelf. --%>
    <div :if={@rolls != [] and !@roll}>
      <.status_strip
        label="Prints in the archive"
        items={[
          %{label: "Rolls", value: length(@rolls)},
          %{label: "Prints", value: @sheets},
          %{label: "Edited", value: @edited}
        ]}
      />

      <section :if={@recent != []} id="recent" class="adm-dr-recent" aria-labelledby="recent-title">
        <h2 id="recent-title" class="adm-dr-heading">Recently edited</h2>
        <ul class="adm-dr-recent-row st-bay">
          <li :for={item <- @recent}>
            <.link
              navigate={~p"/admin/darkroom/#{item.roll}/#{item.print.frame}"}
              class="adm-dr-recent-print"
            >
              <span class="adm-dr-print-picture">
                <img
                  src={Negatives.sized_url(item.print.url, 480)}
                  alt={"Roll #{item.roll}, frame #{item.print.frame}"}
                  loading="lazy"
                  decoding="async"
                />
              </span>
              <span class="adm-dr-print-label">
                <span>
                  Roll {item.roll}, frame <span class="adm-dr-fig">{item.print.frame}</span>
                </span>
                <span class="adm-dr-when">{ago(item.at)}</span>
              </span>
            </.link>
          </li>
        </ul>
      </section>

      <section id="rolls" aria-labelledby="rolls-title">
        <h2 id="rolls-title" class="adm-dr-heading">
          Rolls <span class="adm-count">{length(@rolls)}</span>
        </h2>
        <div class="st-cards adm-dr-rolls">
          <.roll_card :for={roll <- @rolls} roll={roll} />
        </div>
      </section>
    </div>

    <%!-- One roll's prints, on the bay. --%>
    <section
      :if={@roll}
      id="prints"
      class="adm-dr-wall st-bay"
      aria-label={"Prints of roll #{@roll.roll}"}
    >
      <ul class="adm-dr-prints">
        <li :for={print <- @prints}>
          <.link
            navigate={~p"/admin/darkroom/#{@roll.roll}/#{print.frame}"}
            class="adm-dr-print"
            id={"print-#{print.frame}"}
          >
            <span class="adm-dr-print-picture">
              <img
                src={Negatives.sized_url(print.url, 480)}
                alt={"Frame #{print.frame}"}
                loading="lazy"
                decoding="async"
              />
            </span>
            <span class="adm-dr-print-label">
              <span>Frame <span class="adm-dr-fig">{print.frame}</span></span>
              <span class="adm-dr-marks">
                <.pill :if={print.edited} tone="attention">edited</.pill>
                <.pill :if={print.repaired} tone="live">repaired</.pill>
                <.pill :if={print.candidate} tone="held">fill waiting</.pill>
              </span>
            </span>
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  # One roll on the shelf: its contact sheet on the bay, the film, how many
  # prints it has and how many are edited. The card's own link patches to the
  # roll, so the shelf is not fetched again.
  attr :roll, :map, required: true

  defp roll_card(assigns) do
    ~H"""
    <article class="st-card adm-dr-roll" id={"roll-#{@roll.roll}"}>
      <div class="st-card-picture adm-dr-sheet">
        <img
          src={@roll.sheet}
          alt={"Contact sheet of roll #{@roll.roll}"}
          loading="lazy"
          decoding="async"
        />
      </div>
      <div class="st-card-body">
        <h3 class="st-card-title">
          <span class="st-card-mark" aria-hidden="true"></span>
          <.link patch={~p"/admin/darkroom?roll=#{@roll.roll}"} class="st-card-link">
            Roll {@roll.roll}
          </.link>
        </h3>
        <ul class="st-card-state">
          <li class="st-card-line">{@roll.format}, {film(@roll.color)}</li>
          <li class="st-card-line">
            {count(@roll.prints, "print")}, {edited_line(@roll.edited)}
          </li>
        </ul>
        <div
          class="adm-dr-meter"
          role="img"
          aria-label={"#{@roll.edited} of #{@roll.prints} prints edited"}
        >
          <span style={"--share: #{round(100 * @roll.edited / max(@roll.prints, 1))}%"}></span>
        </div>
      </div>
    </article>
    """
  end

  defp film("bw"), do: "black and white"
  defp film("color"), do: "colour"
  defp film(other), do: other

  defp count(1, word), do: "1 #{word}"
  defp count(count, word), do: "#{count} #{word}s"

  defp edited_line(0), do: "none edited"
  defp edited_line(count), do: "#{count} edited"
end
