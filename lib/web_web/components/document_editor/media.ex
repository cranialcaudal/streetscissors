defmodule WebWeb.DocumentEditor.Media do
  @moduledoc """
  The editor's media drawer: the uploaded images (`Web.Blog.Images`) and the
  film archive's rolls and frames (`Web.Negatives`), each with a field for its
  words, inserted at the cursor as the vault writes them:
  `![alt](/uploads/images/x.jpg)` and `![[roll012/3|Caption]]`.

  Opened by the editor's Media button (`pushEventTo` → `"toggle"`); nothing is
  listed until then. It has no forms (it sits inside the host's form), so
  Insert goes through the editor's hook, which reads the words typed and
  sends `"insert"` here. Thumbnails are the public sized copies
  (`Negatives.sized_url/2`), never the darkroom's admin-only pictures, which
  must not end up in a post.
  """
  use WebWeb, :live_component

  alias Web.Negatives

  @rolls 30

  @impl true
  def mount(socket), do: {:ok, assign(socket, open: false, tab: "images", roll: nil)}

  @impl true
  def update(assigns, socket), do: {:ok, assign(socket, id: assigns.id, editor: assigns.editor)}

  @impl true
  def handle_event("toggle", _params, socket), do: {:noreply, assign(socket, open: !socket.assigns.open)}

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(images film),
    do: {:noreply, assign(socket, tab: tab, roll: nil)}

  def handle_event("roll", %{"roll" => roll}, socket),
    do: {:noreply, assign(socket, roll: Negatives.Roll.pad(roll))}

  def handle_event("back", _params, socket), do: {:noreply, assign(socket, roll: nil)}

  def handle_event("insert", params, socket) do
    case snippet(params) do
      nil ->
        {:noreply, socket}

      text ->
        {:noreply,
         socket
         |> assign(open: false)
         |> push_event("editor:insert", %{id: socket.assigns.editor, text: text})}
    end
  end

  @doc """
  The Markdown for an inserted item. Words typed for it lose what would end
  the syntax early (`]`, `|`, a line break).
  """
  def snippet(%{"src" => "/" <> _ = src} = params),
    do: "![#{words(params["words"])}](#{src})"

  def snippet(%{"roll" => roll, "frame" => frame} = params) do
    with true <- frame =~ ~r/\A\d{1,4}\z/,
         padded when padded != "" <- Negatives.Roll.pad(roll),
         true <- padded =~ ~r/\A\d{3,4}\z/ do
      case words(params["words"]) do
        "" -> "![[roll#{padded}/#{String.to_integer(frame)}]]"
        caption -> "![[roll#{padded}/#{String.to_integer(frame)}|#{caption}]]"
      end
    else
      _ -> nil
    end
  end

  def snippet(%{"roll" => roll}) do
    padded = Negatives.Roll.pad(roll)
    if padded =~ ~r/\A\d{3,4}\z/, do: "![[roll#{padded}]]"
  end

  def snippet(_params), do: nil

  defp words(nil), do: ""

  defp words(text),
    do: text |> String.replace(~r/[\]\[|\s]+/, " ") |> String.trim()

  @impl true
  def render(assigns) do
    assigns =
      if assigns.open do
        assign(assigns, items: items(assigns.tab, assigns.roll))
      else
        assign(assigns, items: [])
      end

    ~H"""
    <section id={@id} class="adm-ed-media" hidden={!@open} aria-label="Media to insert">
      <div :if={@open} class="adm-tabs" role="tablist">
        <button
          :for={{tab, label} <- [{"images", "Images"}, {"film", "Film"}]}
          type="button"
          class="adm-tab"
          role="tab"
          aria-selected={to_string(@tab == tab)}
          phx-click="tab"
          phx-value-tab={tab}
          phx-target={@myself}
        >
          {label}
        </button>
        <button :if={@roll} type="button" class="adm-tab" phx-click="back" phx-target={@myself}>
          All rolls
        </button>
      </div>

      <ul :if={@open} class="adm-ed-media-grid">
        <li :for={item <- @items} class="adm-ed-media-item">
          <button
            :if={item.kind == :roll}
            type="button"
            class="adm-ed-tool"
            phx-click="roll"
            phx-value-roll={item.roll}
            phx-target={@myself}
          >
            <img src={item.thumb} alt="" loading="lazy" />
            <span>{item.label}</span>
          </button>
          <%!-- No form: the drawer sits inside the host's form, and forms
               don't nest. The words field has no name, so the host's form
               never sends it; the button hands it over through the editor's
               hook ("editor:media"), which asks this component to insert. --%>
          <div :if={item.kind != :roll} class="adm-ed-media-pick">
            <img src={item.thumb} alt="" loading="lazy" />
            <input
              type="text"
              id={"#{@id}-words-#{item.key}"}
              class="adm-input"
              placeholder={if item.kind == :image, do: "What it shows", else: "Caption"}
              aria-label={"Words for #{item.label}"}
              data-media-words
            />
            <button
              type="button"
              class="adm-btn adm-btn--small"
              phx-click={
                JS.dispatch("editor:media",
                  to: "##{@editor}",
                  detail: %{fields: Map.new(item.fields), words: "#{@id}-words-#{item.key}"}
                )
              }
            >
              Insert {item.label}
            </button>
          </div>
        </li>
        <li :if={@items == []}>Nothing here yet.</li>
      </ul>
    </section>
    """
  end

  defp items("images", _roll) do
    for image <- Web.Blog.Images.list() do
      %{
        kind: :image,
        key: :erlang.phash2(image.path),
        label: image.name,
        thumb: image.path,
        fields: [{"src", image.path}]
      }
    end
  end

  defp items("film", nil) do
    Negatives.list_contact_sheets()
    |> Enum.sort_by(& &1.roll_num, :desc)
    |> Enum.take(@rolls)
    |> Enum.map(fn sheet ->
      %{
        kind: :roll,
        roll: sheet.roll,
        label: "Roll #{sheet.roll}",
        thumb: Negatives.sized_url(sheet.preview_url || sheet.image_url, 480)
      }
    end)
  end

  defp items("film", roll) do
    whole = %{
      kind: :sheet,
      key: "sheet",
      label: "the sheet",
      thumb: sheet_thumb(roll),
      fields: [{"roll", roll}]
    }

    frames =
      for frame <- Negatives.list_frames(roll) do
        %{
          kind: :frame,
          key: "frame-#{frame.frame}",
          label: "frame #{frame.frame}",
          thumb: Negatives.sized_url(frame.url, 480),
          fields: [{"roll", roll}, {"frame", to_string(frame.frame)}]
        }
      end

    [whole | frames]
  end

  defp sheet_thumb(roll) do
    case Enum.find(Negatives.list_contact_sheets(), &(&1.roll == roll)) do
      nil -> nil
      sheet -> Negatives.sized_url(sheet.preview_url || sheet.image_url, 480)
    end
  end
end
