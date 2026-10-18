defmodule WebWeb.AdminLive.Darkroom do
  @moduledoc """
  The prints, roll by roll, to pick one to edit (`/admin/darkroom`). The roll
  shown is in the address (`?roll=065`); with none, the newest roll that has
  prints. A print with a recipe (`Web.Darkroom`) is marked as edited.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Darkroom
  alias Web.Negatives

  def mount(_params, session, socket) do
    if session["admin_user"] do
      rolls =
        for sheet <- Enum.sort_by(Negatives.list_contact_sheets(), & &1.roll_num, :desc),
            prints = Negatives.list_frames(sheet.roll),
            prints != [] do
          %{roll: sheet.roll, format: sheet.format, color: sheet.color, prints: length(prints)}
        end

      {:ok, assign(socket, page_title: "Prints | Admin", rolls: rolls)}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_params(params, _uri, socket) do
    rolls = socket.assigns.rolls
    roll = Enum.find(rolls, &(&1.roll == params["roll"])) || List.first(rolls)

    prints =
      with %{roll: number} <- roll,
           {:ok, dir} <- Negatives.roll_dir(number) do
        for print <- Negatives.list_frames(number) do
          Map.put(print, :edited, Darkroom.edited?(dir, print.frame))
        end
      else
        _ -> []
      end

    {:noreply, assign(socket, roll: roll, prints: prints)}
  end

  def render(assigns) do
    ~H"""
    <.page_head slug="Darkroom / Prints" title="Prints">
      <:lede>
        Pick a print to edit. An edit is kept beside the print as a recipe, and the print
        as it was developed is never lost: Revert puts it back.
      </:lede>
    </.page_head>

    <.empty :if={@rolls == []}>No roll has prints yet.</.empty>

    <nav :if={@rolls != []} class="adm-dr-rolls" aria-label="Rolls">
      <.link
        :for={roll <- @rolls}
        patch={~p"/admin/darkroom?roll=#{roll.roll}"}
        class={["adm-dr-roll", @roll && roll.roll == @roll.roll && "is-current"]}
        aria-current={@roll && roll.roll == @roll.roll && "page"}
      >
        <span class="adm-dr-roll-number">{roll.roll}</span>
        <span class="adm-dr-roll-film">{roll.format} · {film(roll.color)}</span>
        <span class="adm-dr-roll-count">{roll.prints}</span>
      </.link>
    </nav>

    <.panel :if={@roll} title={"Roll #{@roll.roll}"} count={length(@prints)}>
      <ul class="adm-dr-prints">
        <li :for={print <- @prints}>
          <.link
            navigate={~p"/admin/darkroom/#{@roll.roll}/#{print.frame}"}
            class="adm-dr-print"
            id={"print-#{print.frame}"}
          >
            <img
              src={Negatives.sized_url(print.url, 480)}
              alt={"Frame #{print.frame}"}
              loading="lazy"
              decoding="async"
            />
            <span class="adm-dr-print-label">
              Frame {print.frame}
              <.pill :if={print.edited} tone="live">edited</.pill>
            </span>
          </.link>
        </li>
      </ul>
    </.panel>
    """
  end

  defp film("bw"), do: "B&W"
  defp film("color"), do: "colour"
  defp film(other), do: other
end
