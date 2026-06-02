defmodule WebWeb.AdminLive.ContentManager do
  use WebWeb, :live_view

  alias Web.Manuscripts
  alias Web.Audio

  def mount(_params, session, socket) do
    if session["admin_user"] do
      legacy_categories = ["fiction", "reflections", "sensus", "physical", "faith", "non-fiction"]

      manuscripts = load_manuscripts(legacy_categories)
      logs = Audio.list_logs()

      writing_categories = [
        "fitness intelligence",
        "latent sensus",
        "another blog"
      ]

      {:ok,
       assign(socket,
         page_title: "Control Center | Streetscissors",
         manuscripts: manuscripts,
         writing_categories: writing_categories,
         selected_category: "all",
         logs: logs,
         upload_categories: %{}
       )
       |> allow_upload(:markdown,
         accept: ~w(.md),
         max_entries: 20,
         max_file_size: 10_000_000
       )
       |> allow_upload(:audio,
         accept: ~w(.mp3 .wav .m4a .webm),
         max_entries: 5,
         max_file_size: 50_000_000
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  defp load_manuscripts(legacy_categories) do
    Enum.flat_map(legacy_categories, fn legacy_cat ->
      Manuscripts.list_files(legacy_cat)
      |> Enum.map(fn m ->
        display_cat =
          case legacy_cat do
            "sensus" -> "latent sensus"
            "physical" -> "fitness intelligence"
            _ -> "another blog"
          end

        m
        |> Map.put(:category, display_cat)
        |> Map.put(:category_folder, legacy_cat)
      end)
    end)
  end

  def handle_event("filter_category", %{"category" => category}, socket) do
    {:noreply, assign(socket, selected_category: category)}
  end

  def handle_event("delete_manuscript", %{"category" => cat, "slug" => slug}, socket) do
    Manuscripts.delete_manuscript(cat, slug)
    legacy_categories = ["fiction", "reflections", "sensus", "physical", "faith", "non-fiction"]

    {:noreply,
     assign(socket, manuscripts: load_manuscripts(legacy_categories))
     |> put_flash(:info, "Redacted.")}
  end

  def handle_event("validate_upload", %{"upload_categories" => cats}, socket) do
    {:noreply, assign(socket, upload_categories: cats)}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref, "type" => "markdown"}, socket) do
    {:noreply, cancel_upload(socket, :markdown, ref)}
  end

  def handle_event("cancel_upload", %{"ref" => ref, "type" => "audio"}, socket) do
    {:noreply, cancel_upload(socket, :audio, ref)}
  end

  def handle_event("ingest_files", _params, socket) do
    consume_uploaded_entries(socket, :markdown, fn %{path: path}, entry ->
      content = File.read!(path)
      clean_name = Path.basename(entry.client_name, ".md")
      slug = slugify(clean_name)

      category = Map.get(socket.assigns.upload_categories, entry.ref) || "latent sensus"

      folder =
        case category do
          "latent sensus" -> "sensus"
          "fitness intelligence" -> "physical"
          _ -> "reflections"
        end

      Manuscripts.create_manuscript(folder, slug, content)
      {:ok, :created}
    end)

    consume_uploaded_entries(socket, :audio, fn %{path: path}, entry ->
      uploads_dir = Path.join(["priv", "static", "uploads"])
      File.mkdir_p!(uploads_dir)

      # Extract original extension securely
      ext = Path.extname(entry.client_name) |> String.downcase()
      clean_name = Path.basename(entry.client_name, ext) |> slugify()
      filename = "#{clean_name}-#{System.unique_integer([:positive])}#{ext}"
      dest_path = Path.join(uploads_dir, filename)

      File.cp!(path, dest_path)
      web_path = "/uploads/#{filename}"

      stardate = calculate_stardate()

      Audio.create_log(%{
        title: entry.client_name,
        stardate: stardate,
        file_path: web_path,
        duration: 0,
        description: "Uploaded via terminal.",
        published: true
      })

      {:ok, :created}
    end)

    legacy_categories = ["fiction", "reflections", "sensus", "physical", "faith", "non-fiction"]

    {:noreply,
     socket
     |> put_flash(:info, "Intel Ingested.")
     |> assign(
       manuscripts: load_manuscripts(legacy_categories),
       logs: Audio.list_logs(),
       upload_categories: %{}
     )}
  end

  def handle_event("toggle_audio_status", %{"id" => id}, socket) do
    log = Audio.get_log!(id)
    {:ok, _log} = Audio.update_log(log, %{published: !log.published})
    {:noreply, assign(socket, logs: Audio.list_logs())}
  end

  def handle_event("delete_log", %{"id" => id}, socket) do
    log = Audio.get_log!(id)
    Audio.delete_log(log)
    {:noreply, assign(socket, logs: Audio.list_logs())}
  end

  defp slugify(string) do
    string
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  defp calculate_stardate do
    now = NaiveDateTime.utc_now()
    day = Date.day_of_year(now)
    "4#{now.year - 2000}.#{trunc(day * 2.7)}"
  end

  def render(assigns) do
    ~H"""
    <div class="mission-control" style="border-radius: 8px;">
      <main class="workspace">
        <header class="workspace-header">
          <div class="header-info">
            <h1 class="workspace-title">Ingestion Terminal</h1>
            <p class="workspace-subtitle">Syncing frequencies with the collective.</p>
          </div>
        </header>

        <div class="workspace-content">
          <div class="ingestion-terminal">
            <form id="mkdn-upload-form" phx-change="validate_upload" phx-submit="ingest_files">
              <div class="terminal-shell">
                <div class="terminal-header">
                  <div class="dots"><span></span><span></span><span></span></div>
                  <div class="command-title">INGEST_INTELLIGENCE_V3.sh</div>
                </div>

                <div class="terminal-body" phx-drop-target={@uploads.markdown.ref}>
                  <div
                    class="drop-zones"
                    style="display: grid; grid-template-columns: 1fr 1fr; gap: 2rem;"
                  >
                    <!-- Markdown Drop Zone -->
                    <div class="drop-zone" phx-drop-target={@uploads.markdown.ref}>
                      <div style="margin-bottom: 1rem; color: var(--accent-primary);"><.icon name="hero-document-text" class="size-8" /></div>
                      <h3>MARKDOWN</h3>
                      <p>
                        Drag .md here or
                        <label class="action-link">
                          PICK FILES<.live_file_input upload={@uploads.markdown} class="hidden-input" />
                        </label>
                      </p>
                    </div>
                    
    <!-- Audio Drop Zone -->
                    <div class="drop-zone" phx-drop-target={@uploads.audio.ref}>
                      <div style="margin-bottom: 1rem; color: #a78bfa;"><.icon name="hero-microphone" class="size-8" /></div>
                      <h3>AUDIO LOGS</h3>
                      <p>
                        Drag audio here or
                        <label class="action-link" style="color: #a78bfa;">
                          PICK FILES<.live_file_input upload={@uploads.audio} class="hidden-input" />
                        </label>
                      </p>
                    </div>
                  </div>
                  
    <!-- Staged Files -->
                  <div
                    :if={
                      !Enum.empty?(@uploads.markdown.entries) || !Enum.empty?(@uploads.audio.entries)
                    }
                    class="staged-queue"
                    style="margin-top: 2rem; border-top: 1px solid #222; padding-top: 2rem;"
                  >
                    <h4 style="color: #888; font-size: 0.8rem; margin-bottom: 1rem; letter-spacing: 1px;">
                      STAGED FOR INGESTION
                    </h4>

                    <%= for entry <- @uploads.markdown.entries do %>
                      <div class="staged-card">
                        <div class="card-info">
                          <span class="file-icon">
                            <.icon name="hero-document-text" class="size-4" />
                          </span>
                          <div class="file-details">
                            <span class="file-name">{entry.client_name}</span>
                            <div class="progress-wrap">
                              <div class="progress-bar" style={"width: #{entry.progress}%"}></div>
                            </div>
                          </div>
                        </div>
                        <div class="card-config">
                          <select name={"upload_categories[#{entry.ref}]"} class="minimal-select">
                            <option
                              value="latent sensus"
                              selected={Map.get(@upload_categories, entry.ref) == "latent sensus"}
                            >
                              LATENT SENSUS
                            </option>
                            <option
                              value="fitness intelligence"
                              selected={
                                Map.get(@upload_categories, entry.ref) == "fitness intelligence"
                              }
                            >
                              FITNESS INTEL
                            </option>
                            <option
                              value="another blog"
                              selected={Map.get(@upload_categories, entry.ref) == "another blog"}
                            >
                              ANOTHER BLOG
                            </option>
                          </select>
                          <button
                            type="button"
                            phx-click="cancel_upload"
                            phx-value-ref={entry.ref}
                            phx-value-type="markdown"
                            class="purge-btn"
                          >
                            <.icon name="hero-trash" class="size-4" />
                          </button>
                        </div>
                      </div>
                    <% end %>

                    <%= for entry <- @uploads.audio.entries do %>
                      <div class="staged-card" style="border-left: 2px solid #a78bfa;">
                        <div class="card-info">
                          <span class="file-icon" style="color: #a78bfa;">
                            <.icon name="hero-microphone" class="size-4" />
                          </span>
                          <div class="file-details">
                            <span class="file-name">{entry.client_name}</span>
                            <div class="progress-wrap">
                              <div
                                class="progress-bar"
                                style={"width: #{entry.progress}%; background: #a78bfa;"}
                              >
                              </div>
                            </div>
                          </div>
                        </div>
                        <div class="card-config">
                          <span style="color: #888; font-size: 0.8rem; font-family: monospace;">
                            AUDIO
                          </span>
                          <button
                            type="button"
                            phx-click="cancel_upload"
                            phx-value-ref={entry.ref}
                            phx-value-type="audio"
                            class="purge-btn"
                          >
                            <.icon name="hero-trash" class="size-4" />
                          </button>
                        </div>
                      </div>
                    <% end %>

                    <div class="launch-sequence">
                      <button type="submit" class="launch-btn">
                        <span class="btn-text">
                          INITIALIZE COMMIT ({length(@uploads.markdown.entries) +
                            length(@uploads.audio.entries)} UNITS)
                        </span>
                        <div class="btn-glow"></div>
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </form>
          </div>
          
    <!-- Tabs for Viewing Content -->
          <div style="display: flex; gap: 2rem; margin-bottom: 2rem; border-bottom: 1px solid #222; padding-bottom: 1rem;">
            <h2 style="font-size: 1.2rem; font-weight: 800; letter-spacing: 1px;">ARCHIVES</h2>
          </div>
          
    <!-- Markdown Filter -->
          <div class="filters-bar" style="margin-bottom: 1rem;">
            <div class="category-pills">
              <button
                phx-click="filter_category"
                phx-value-category="all"
                class={["pill", @selected_category == "all" && "active"]}
              >
                All MD
              </button>
              <%= for cat <- @writing_categories do %>
                <button
                  phx-click="filter_category"
                  phx-value-category={cat}
                  class={["pill", @selected_category == cat && "active"]}
                >
                  {String.capitalize(cat)}
                </button>
              <% end %>
            </div>
          </div>

          <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 4rem;">
            <!-- Manuscripts -->
            <div class="items-list" style="display: flex; flex-direction: column; gap: 1rem;">
              <%= for man <- Enum.filter(@manuscripts, fn m -> @selected_category == "all" or m.category == @selected_category end) do %>
                <div class="writing-item manuscript" style="padding: 1.5rem; min-height: auto;">
                  <div class="item-main">
                    <div class="item-type"><i class="fas fa-scroll"></i> MARKDOWN</div>
                    <h3 class="item-title" style="font-size: 1.1rem; margin-bottom: 0.5rem;">
                      {man.title}
                    </h3>
                    <div class="item-meta" style="padding-top: 0; border: none; margin-top: 0;">
                      <span class="tag pill-sm">{man.category}</span>
                      <span class="mtime">{Calendar.strftime(man.mtime, "%b %d")}</span>
                    </div>
                  </div>
                  <div class="item-actions">
                    <button
                      phx-click="delete_manuscript"
                      phx-value-category={man.category_folder}
                      phx-value-slug={man.slug}
                      class="icon-btn delete"
                      phx-confirm="Purge?"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
            
    <!-- Audio Logs -->
            <div class="items-list" style="display: flex; flex-direction: column; gap: 1rem;">
              <%= for log <- @logs do %>
                <div
                  class="writing-item"
                  style="padding: 1.5rem; min-height: auto; border-left: 2px solid #a78bfa;"
                >
                  <div class="item-main">
                    <div class="item-type" style="color: #a78bfa;">
                      <i class="fas fa-microphone"></i> AUDIO LOG
                    </div>
                    <h3 class="item-title" style="font-size: 1.1rem; margin-bottom: 0.5rem;">
                      {log.title}
                    </h3>
                    <div
                      class="item-meta"
                      style="padding-top: 0; border: none; margin-top: 0; display: flex; gap: 1rem;"
                    >
                      <span class="mtime">STARDATE {log.stardate}</span>
                      <button
                        phx-click="toggle_audio_status"
                        phx-value-id={log.id}
                        class="text-link"
                        style={"font-size: 0.7rem; color: " <> if(log.published, do: "#4ade80", else: "#ff6b6b")}
                      >
                        {if log.published, do: "LIVE", else: "HIDDEN"}
                      </button>
                    </div>
                  </div>
                  <div class="item-actions">
                    <button
                      phx-click="delete_log"
                      phx-value-id={log.id}
                      class="icon-btn delete"
                      phx-confirm="Purge?"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </main>

      <style>
        @import url('https://fonts.googleapis.com/css2?family=Outfit:wght@300;500;800&family=JetBrains+Mono:wght@400;700&display=swap');
        :root { --panel-bg: rgba(10, 10, 12, 0.98); --border-color: rgba(255, 255, 255, 0.08); --accent-primary: #ff6600; --accent-secondary: #00f2ff; --text-muted: #666; --sidebar-width: 240px; --glass-surface: rgba(255, 255, 255, 0.02); }
        .mission-control { display: flex; height: 100%; min-height: 80vh; background: #000; color: #fff; font-family: 'Outfit', sans-serif; overflow: hidden; }
        .workspace { flex: 1; display: flex; flex-direction: column; overflow: hidden; background: radial-gradient(circle at 70% 20%, rgba(255, 102, 0, 0.05), transparent 50%), #000; }
        .workspace-header { padding: 3rem 4rem; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid var(--border-color); }
        .workspace-title { font-size: 2.2rem; font-weight: 800; margin: 0; letter-spacing: -1px; background: linear-gradient(to bottom, #fff, #888); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .workspace-subtitle { color: #555; margin: 0.5rem 0 0 0; font-size: 1rem; }
        .workspace-content { flex: 1; overflow-y: auto; padding: 3rem 4rem; position: relative; }
        ::-webkit-scrollbar { width: 10px; } ::-webkit-scrollbar-track { background: transparent; } ::-webkit-scrollbar-thumb { background: #1a1a1a; border: 3px solid #000; border-radius: 10px; }

        .ingestion-terminal { max-width: 1200px; margin: 0 auto 2rem; width: 100%; }
        .terminal-shell { background: #0a0a0c; border: 1px solid #1a1a1c; border-radius: 12px; overflow: hidden; box-shadow: 0 40px 100px rgba(0,0,0,0.8); }
        .terminal-header { background: #151518; padding: 0.8rem 1.2rem; display: flex; align-items: center; gap: 1.5rem; border-bottom: 1px solid #1a1a1c; }
        .dots { display: flex; gap: 0.4rem; } .dots span { width: 8px; height: 8px; border-radius: 50%; background: #333; }
        .command-title { font-family: 'JetBrains Mono'; font-size: 0.7rem; color: #555; letter-spacing: 1px; }

        .terminal-body { padding: 3rem; min-height: 240px; }
        .drop-zone { background: rgba(255,255,255,0.02); border: 2px dashed #333; border-radius: 12px; padding: 3rem 2rem; text-align: center; transition: all 0.3s; }
        .drop-zone:hover { border-color: #666; background: rgba(255,255,255,0.04); }
        .drop-zone h3 { font-size: 0.9rem; font-weight: 800; letter-spacing: 2px; margin-bottom: 0.5rem; color: #fff; }
        .drop-zone p { color: #555; font-size: 0.8rem; }

        .action-link { cursor: pointer; text-decoration: underline; text-underline-offset: 4px; font-weight: 800; color: var(--accent-primary); }
        .hidden-input { display: none; }

        .staged-queue { display: flex; flex-direction: column; gap: 1.2rem; }
        .staged-card { background: #000; border: 1px solid #111; padding: 1rem 1.5rem; border-radius: 10px; display: flex; justify-content: space-between; align-items: center; transition: all 0.3s; }
        .card-info { display: flex; align-items: center; gap: 1.5rem; flex: 1; }
        .file-icon { font-size: 1.4rem; color: var(--accent-primary); }
        .file-details { flex: 1; display: flex; flex-direction: column; gap: 0.5rem; }
        .file-name { font-family: 'JetBrains Mono'; font-size: 0.85rem; color: #fff; }
        .progress-wrap { height: 3px; background: #111; border-radius: 2px; overflow: hidden; width: 100%; max-width: 250px; }
        .progress-bar { height: 100%; background: var(--accent-primary); transition: width 0.3s; }

        .card-config { display: flex; align-items: center; gap: 1.5rem; }
        .minimal-select { background: #111; border: 1px solid #222; color: #888; padding: 0.5rem 1rem; border-radius: 6px; font-family: 'JetBrains Mono'; font-size: 0.7rem; cursor: pointer; outline: none; }
        .minimal-select:focus { border-color: var(--accent-primary); color: #fff; }
        .purge-btn { background: none; border: none; color: #333; cursor: pointer; transition: color 0.2s; font-size: 1rem; }
        .purge-btn:hover { color: #f00; }

        .launch-sequence { margin-top: 2rem; border-top: 1px solid #111; padding-top: 2rem; display: flex; justify-content: center; }
        .launch-btn { background: #fff; color: #000; border: none; padding: 1rem 2.5rem; border-radius: 8px; font-weight: 900; font-size: 0.8rem; letter-spacing: 2px; position: relative; cursor: pointer; overflow: hidden; transition: all 0.3s; }
        .launch-btn:hover { transform: scale(1.02); }
        .btn-glow { position: absolute; inset: 0; background: linear-gradient(45deg, transparent, rgba(255,255,255,0.2), transparent); animation: sweep 2s infinite; }
        @keyframes sweep { 0% { transform: translateX(-100%); } 100% { transform: translateX(100%); } }

        .filters-bar { padding: 0; border-radius: 20px; }
        .category-pills { display: flex; gap: 1rem; }
        .pill { padding: 0.4rem 1.2rem; border-radius: 30px; background: transparent; color: #666; cursor: pointer; border: 1px solid rgba(255,255,255,0.05); font-weight: 500; transition: all 0.3s; font-size: 0.8rem; }
        .pill.active { background: #fff; color: #000; border-color: #fff; }

        .writing-item { background: #080808; border: 1px solid var(--border-color); border-radius: 12px; display: flex; flex-direction: column; position: relative; transition: all 0.3s; }
        .writing-item:hover { border-color: rgba(255, 102, 0, 0.3); background: #0c0c0e; }
        .item-type { font-size: 0.65rem; color: #444; margin-bottom: 0.5rem; letter-spacing: 2px; font-weight: 800; display: flex; align-items: center; gap: 0.6rem; }
        .item-title { font-size: 1.1rem; font-weight: 500; color: #fff; line-height: 1.25; }
        .item-meta { display: flex; align-items: center; justify-content: space-between; margin-top: auto; }
        .pill-sm { font-size: 0.65rem; color: #888; font-weight: 800; text-transform: uppercase; letter-spacing: 1px; }
        .mtime { font-size: 0.65rem; color: #555; font-family: 'JetBrains Mono'; }

        .item-actions { position: absolute; top: 1rem; right: 1rem; display: flex; gap: 0.5rem; opacity: 0; transition: opacity 0.3s; }
        .writing-item:hover .item-actions { opacity: 1; }
        .icon-btn { width: 30px; height: 30px; border-radius: 8px; background: #000; border: 1px solid #222; color: #666; cursor: pointer; transition: all 0.2s; display: flex; align-items: center; justify-content: center; font-size: 0.8rem; }
        .icon-btn:hover { color: #fff; border-color: #444; background: #111; }
        .icon-btn.delete:hover { border-color: #f00; color: #f00; }
        .text-link { background: none; border: none; cursor: pointer; padding: 0; font-weight: bold; }
        .text-link:hover { text-decoration: underline; }
      </style>
    </div>
    """
  end
end
