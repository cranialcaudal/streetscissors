defmodule WebWeb.AdminLive.Keywords do
  @moduledoc """
  The one vocabulary the blog and the logs are filed under, on one page: every
  keyword, what carries it, and a way to rename it everywhere at once
  (`Web.Keywords.Index`).

  Renaming to a keyword that already exists merges the two, which is how a
  misspelling or a near-duplicate (`nyc`, `new-york`) is put right. `?show=once`
  narrows the list to keywords only one piece carries, where those usually are.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Audio.Log
  alias Web.Keywords.Index

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok, socket |> assign(page_title: "Keywords | Admin", renaming: nil) |> load()}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :show, if(params["show"] == "once", do: "once", else: "all"))}
  end

  def handle_event("rename", %{"keyword" => keyword}, socket) do
    {:noreply, assign(socket, :renaming, keyword)}
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :renaming, nil)}

  def handle_event("save", %{"from" => from, "to" => to}, socket) do
    case Index.rename(from, to) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:renaming, nil)
         |> load()
         |> put_flash(:info, done(from, result))}

      {:error, :same} ->
        {:noreply, put_flash(socket, :error, "That is the keyword it already is.")}

      {:error, :blank} ->
        {:noreply, put_flash(socket, :error, "A keyword needs at least one letter or number.")}

      {:error, :unknown} ->
        {:noreply, socket |> load() |> put_flash(:error, "Nothing carries #{from} any more.")}
    end
  end

  defp done(from, %{keyword: to, posts: posts, logs: logs, merged: merged}) do
    verb = if merged, do: "Merged #{from} into #{to}", else: "Renamed #{from} to #{to}"
    "#{verb}: #{count(posts, "post")}, #{count(logs, "log")}."
  end

  defp count(1, word), do: "1 #{word}"
  defp count(n, word), do: "#{n} #{word}s"

  defp load(socket), do: assign(socket, :usage, Index.usage())

  def render(assigns) do
    once = Index.singletons(assigns.usage)

    assigns =
      assigns
      |> assign(:once_count, length(once))
      |> assign(:shown, if(assigns.show == "once", do: once, else: assigns.usage))
      |> assign(:names, Enum.map(assigns.usage, & &1.keyword))

    ~H"""
    <.page_head slug="Write / Keywords" title="Keywords">
      <:lede>
        What the blog and the logs are filed under. A keyword renamed here is rewritten in every
        post's file and every log that carries it; renamed to one that already exists, the two
        become one.
      </:lede>
    </.page_head>

    <.panel title="In use" count={length(@usage)}>
      <.tabs label="Keywords">
        <:tab patch={~p"/admin/keywords"} active={@show == "all"} count={length(@usage)}>All</:tab>
        <:tab patch={~p"/admin/keywords?show=once"} active={@show == "once"} count={@once_count}>
          Used once
        </:tab>
      </.tabs>

      <.empty :if={@shown == []}>
        {if @show == "once",
          do: "Every keyword is carried by more than one piece.",
          else: "No keywords yet."}
      </.empty>

      <%!-- Offered as the rename field is typed in, so a merge is a choice
            from the list rather than a guess at the spelling. --%>
      <datalist id="keyword-names">
        <option :for={name <- @names} value={name}></option>
      </datalist>

      <div :if={@shown != []} class="adm-list" id="keywords">
        <article :for={entry <- @shown} id={"keyword-#{entry.keyword}"} class="adm-item">
          <div class="adm-item-main">
            <h2 class="adm-item-title adm-item-title--mono">{entry.keyword}</h2>
            <div class="adm-item-meta">
              <span>{count(length(entry.posts), "post")}</span>
              <span>{count(length(entry.logs), "log")}</span>
              <.pill :if={entry.count == 1} tone="held">used once</.pill>
            </div>
            <div class="adm-item-meta">
              <.link
                :for={post <- entry.posts}
                navigate={~p"/admin/blog/#{post.slug}/edit"}
                class="adm-link"
              >
                {post.title}{if post.draft, do: " (draft)"}
              </.link>
              <.link :for={log <- entry.logs} navigate={~p"/admin/logs"} class="adm-link">
                Log, {Log.title(log)}{if !log.published, do: " (unpublished)"}
              </.link>
            </div>

            <form
              :if={@renaming == entry.keyword}
              id={"rename-#{entry.keyword}"}
              phx-submit="save"
              class="adm-inline-form"
            >
              <input type="hidden" name="from" value={entry.keyword} />
              <input
                type="text"
                name="to"
                class="adm-input"
                value={entry.keyword}
                list="keyword-names"
                autocomplete="off"
                aria-label={"New name for #{entry.keyword}"}
                phx-mounted={JS.focus()}
                required
              />
              <button type="submit" class="adm-btn adm-btn--small">Rename everywhere</button>
              <button type="button" phx-click="cancel" class="adm-link adm-link--quiet">
                Cancel
              </button>
            </form>
          </div>

          <div class="adm-item-actions">
            <.link href={~p"/blog?keyword=#{entry.keyword}"} target="_blank" class="adm-link">
              On the blog <.icon name="hero-arrow-top-right-on-square" class="size-4" />
            </.link>
            <button
              :if={@renaming != entry.keyword}
              phx-click="rename"
              phx-value-keyword={entry.keyword}
              class="adm-link"
            >
              Rename or merge
            </button>
          </div>
        </article>
      </div>
    </.panel>
    """
  end
end
