defmodule WebWeb.AdminLive.ContentManager do
  use WebWeb, :live_view

  alias Web.Manuscripts
  alias Web.Audio

  def mount(_params, session, socket) do
    if session["admin_user"] do
      destinations = [
        "Latent Sensus (Blog)",
        "Fitness Intelligence (Blog)",
        "Another Blog",
        "Audio Logs",
        "Image Gallery"
      ]

      {:ok,
       assign(socket,
         page_title: "Ingestion Hub | Streetscissors",
         destinations: destinations,
         selected_destination: hd(destinations),
         manuscripts: load_manuscripts(),
         logs: Audio.list_logs(),
         images: list_images(),
         recent_uploads: []
       )
       |> allow_upload(:file,
         accept: ~w(.md .mp3 .wav .m4a .webm .jpg .jpeg .png .gif .webp),
         max_entries: 10,
         max_file_size: 50_000_000,
         auto_upload: true,
         progress: &handle_progress/3
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  defp load_manuscripts do
    legacy_categories = ["fiction", "reflections", "sensus", "physical", "faith", "non-fiction"]

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
    |> Enum.sort_by(& &1.mtime, {:desc, Date})
  end

  defp list_images do
    images_dir = Path.join(["priv", "static", "images", "uploads"])
    File.mkdir_p!(images_dir)

    case File.ls(images_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.match?(&1, ~r/\.(jpg|jpeg|png|gif|webp)$/i))
        |> Enum.map(fn f ->
          stat = File.stat!(Path.join(images_dir, f))
          %{name: f, path: "/images/uploads/#{f}", mtime: stat.mtime}
        end)
        |> Enum.sort_by(& &1.mtime, :desc)

      _ ->
        []
    end
  end

  def handle_event("select_destination", %{"destination" => dest}, socket) do
    {:noreply, assign(socket, selected_destination: dest)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_manuscript", %{"category" => cat, "slug" => slug}, socket) do
    Manuscripts.delete_manuscript(cat, slug)
    {:noreply, assign(socket, manuscripts: load_manuscripts()) |> put_flash(:info, "Redacted.")}
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

  def handle_event("delete_image", %{"name" => name}, socket) do
    path = Path.join(["priv", "static", "images", "uploads", name])
    File.rm(path)
    {:noreply, assign(socket, images: list_images()) |> put_flash(:info, "Image purged.")}
  end

  defp handle_progress(:file, entry, socket) do
    if entry.done? do
      destination = socket.assigns.selected_destination

      consumed =
        consume_uploaded_entries(socket, :file, fn %{path: path}, meta ->
          process_file(path, meta.client_name, destination)
        end)

      socket =
        socket
        |> assign(
          manuscripts: load_manuscripts(),
          logs: Audio.list_logs(),
          images: list_images(),
          recent_uploads: consumed ++ socket.assigns.recent_uploads
        )
        |> put_flash(:info, "Intel successfully routed to #{destination}.")

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp process_file(path, client_name, destination) do
    ext = Path.extname(client_name) |> String.downcase()
    clean_name = Path.basename(client_name, ext) |> slugify()

    cond do
      ext == ".md" ->
        content = File.read!(path)

        folder =
          case destination do
            "Latent Sensus (Blog)" -> "sensus"
            "Fitness Intelligence (Blog)" -> "physical"
            _ -> "reflections"
          end

        Manuscripts.create_manuscript(folder, clean_name, content)
        {:ok, %{type: :markdown, name: clean_name, folder: folder}}

      ext in [".mp3", ".wav", ".m4a", ".webm"] ->
        uploads_dir = Path.join(["priv", "static", "uploads"])
        File.mkdir_p!(uploads_dir)
        filename = "#{clean_name}-#{System.unique_integer([:positive])}#{ext}"
        dest_path = Path.join(uploads_dir, filename)
        File.cp!(path, dest_path)

        web_path = "/uploads/#{filename}"
        stardate = calculate_stardate()

        Audio.create_log(%{
          title: client_name,
          stardate: stardate,
          file_path: web_path,
          duration: 0,
          description: "Uploaded via hub.",
          published: true
        })

        {:ok, %{type: :audio, name: client_name}}

      ext in [".jpg", ".jpeg", ".png", ".gif", ".webp"] ->
        images_dir = Path.join(["priv", "static", "images", "uploads"])
        File.mkdir_p!(images_dir)
        filename = "#{clean_name}-#{System.unique_integer([:positive])}#{ext}"
        dest_path = Path.join(images_dir, filename)
        File.cp!(path, dest_path)

        web_path = "/images/uploads/#{filename}"

        {:ok,
         %{type: :image, name: filename, url: web_path, markdown: "![#{clean_name}](#{web_path})"}}

      true ->
        {:ok, %{type: :error, message: "Unknown file type."}}
    end
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
            <h1 class="workspace-title">Central Upload Hub</h1>
            <p class="workspace-subtitle">Drop files to instantly route them to their destination.</p>
          </div>
        </header>

        <div class="workspace-content">
          <div class="ingestion-terminal">
            <form id="upload-form" phx-change="validate">
              <div class="terminal-shell">
                <div class="terminal-header" style="justify-content: space-between;">
                  <div style="display: flex; gap: 1.5rem; align-items: center;">
                    <div class="dots"><span></span><span></span><span></span></div>
                    <div class="command-title">AUTO_ROUTER.sh</div>
                  </div>

                  <div style="display: flex; align-items: center; gap: 1rem;">
                    <span style="color: #888; font-size: 0.8rem; font-family: 'JetBrains Mono';">
                      TARGET DESTINATION:
                    </span>
                    <select
                      name="destination"
                      phx-change="select_destination"
                      class="minimal-select"
                      style="font-size: 0.9rem; padding: 0.5rem 2rem 0.5rem 1rem; border-color: var(--accent-primary); color: #fff;"
                    >
                      <%= for dest <- @destinations do %>
                        <option value={dest} selected={@selected_destination == dest}>
                          {String.upcase(dest)}
                        </option>
                      <% end %>
                    </select>
                  </div>
                </div>

                <div
                  class="terminal-body drop-zone-master"
                  phx-drop-target={@uploads.file.ref}
                >
                  <div style="display: flex; flex-direction: column; align-items: center; gap: 1.5rem;">
                    <div style="color: var(--accent-primary);">
                      <.icon name="hero-cloud-arrow-up" class="size-12 primary-pulse" />
                    </div>
                    <div>
                      <h2 style="font-size: 1.5rem; font-weight: 800; letter-spacing: 2px; color: #fff; text-align: center; margin-bottom: 0.5rem;">
                        DROP SECURE FILES HERE
                      </h2>
                      <p style="color: #888; text-align: center; font-family: 'JetBrains Mono'; font-size: 0.9rem;">
                        Routing to:
                        <strong style="color: var(--accent-primary);">
                          {String.upcase(@selected_destination)}
                        </strong>
                      </p>
                    </div>

                    <p style="color: #555; font-size: 0.8rem;">
                      Accepts: .md, .mp3, .wav, .jpg, .png, .gif
                    </p>

                    <label class="launch-btn" style="cursor: pointer; display: inline-block;">
                      <span class="btn-text">BROWSE FILES</span>
                      <div class="btn-glow"></div>
                      <.live_file_input upload={@uploads.file} class="hidden-input" />
                    </label>
                  </div>
                  
    <!-- Upload Progress -->
                  <div
                    :if={!Enum.empty?(@uploads.file.entries)}
                    class="staged-queue"
                    style="margin-top: 3rem; border-top: 1px solid #222; padding-top: 2rem;"
                  >
                    <%= for entry <- @uploads.file.entries do %>
                      <div class="staged-card">
                        <div class="card-info">
                          <span class="file-icon">
                            <.icon name="hero-document-arrow-up" class="size-5" />
                          </span>
                          <div class="file-details">
                            <span class="file-name">{entry.client_name}</span>
                            <div class="progress-wrap">
                              <div class="progress-bar" style={"width: #{entry.progress}%"}></div>
                            </div>
                          </div>
                        </div>
                        <div class="card-config">
                          <span style="color: var(--accent-primary); font-size: 0.8rem; font-family: monospace;">
                            UPLOADING...
                          </span>
                        </div>
                      </div>
                    <% end %>
                  </div>
                  
    <!-- Upload Results / Copy Links -->
                  <div
                    :if={!Enum.empty?(@recent_uploads)}
                    class="results-queue"
                    style="margin-top: 2rem;"
                  >
                    <h4 style="color: #4ade80; font-size: 0.8rem; margin-bottom: 1rem; letter-spacing: 1px; font-family: 'JetBrains Mono';">
                      RECENTLY ROUTED:
                    </h4>
                    <%= for result <- @recent_uploads do %>
                      <div
                        class="staged-card"
                        style="border-left: 2px solid #4ade80; background: rgba(74, 222, 128, 0.05);"
                      >
                        <div class="card-info">
                          <span class="file-icon" style="color: #4ade80;">
                            <.icon name="hero-check-circle" class="size-5" />
                          </span>
                          <div class="file-details">
                            <%= case result do %>
                              <% %{type: :image, markdown: md} -> %>
                                <span class="file-name">Image Uploaded</span>
                                <div style="display: flex; gap: 1rem; align-items: center; margin-top: 0.5rem;">
                                  <input
                                    type="text"
                                    value={md}
                                    readonly
                                    class="minimal-select"
                                    style="flex: 1; color: #fff; border-color: #333;"
                                    onclick="this.select(); document.execCommand('copy');"
                                  />
                                  <span style="color: #888; font-size: 0.7rem;">
                                    (Click to copy markdown)
                                  </span>
                                </div>
                              <% %{type: :markdown, name: name} -> %>
                                <span class="file-name">Markdown '{name}' routed successfully.</span>
                              <% %{type: :audio, name: name} -> %>
                                <span class="file-name">
                                  Audio log '{name}' archived successfully.
                                </span>
                              <% _ -> %>
                                <span class="file-name">Processing complete.</span>
                            <% end %>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </form>
          </div>
          
    <!-- Archives Below -->
          <div style="display: flex; gap: 2rem; margin-bottom: 2rem; border-bottom: 1px solid #222; padding-bottom: 1rem; margin-top: 4rem;">
            <h2 style="font-size: 1.2rem; font-weight: 800; letter-spacing: 1px;">
              ARCHIVES EXPLORER
            </h2>
          </div>

          <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 2rem;">
            
    <!-- Markdown Column -->
            <div class="archive-column">
              <h3 style="color: #888; font-size: 0.9rem; letter-spacing: 2px; margin-bottom: 1.5rem;">
                MARKDOWN POSTS
              </h3>
              <div class="items-list" style="display: flex; flex-direction: column; gap: 1rem;">
                <%= for man <- Enum.take(@manuscripts, 10) do %>
                  <div class="writing-item manuscript" style="padding: 1.5rem; min-height: auto;">
                    <div class="item-main">
                      <div class="item-type">
                        <i class="fas fa-scroll"></i> {String.upcase(man.category)}
                      </div>
                      <h3 class="item-title" style="font-size: 1.1rem; margin-bottom: 0.5rem;">
                        {man.title}
                      </h3>
                      <div class="item-meta" style="padding-top: 0; border: none; margin-top: 0;">
                        <span class="mtime">{Calendar.strftime(man.mtime, "%b %d, %Y")}</span>
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
            </div>
            
    <!-- Audio Column -->
            <div class="archive-column">
              <h3 style="color: #a78bfa; font-size: 0.9rem; letter-spacing: 2px; margin-bottom: 1.5rem;">
                AUDIO LOGS
              </h3>
              <div class="items-list" style="display: flex; flex-direction: column; gap: 1rem;">
                <%= for log <- Enum.take(@logs, 10) do %>
                  <div
                    class="writing-item"
                    style="padding: 1.5rem; min-height: auto; border-left: 2px solid #a78bfa;"
                  >
                    <div class="item-main">
                      <h3 class="item-title" style="font-size: 1.1rem; margin-bottom: 0.5rem;">
                        {log.title}
                      </h3>
                      <div
                        class="item-meta"
                        style="padding-top: 0; border: none; margin-top: 0; display: flex; gap: 1rem; align-items: center;"
                      >
                        <span class="mtime">SD {log.stardate}</span>
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
            
    <!-- Image Column -->
            <div class="archive-column">
              <h3 style="color: #60a5fa; font-size: 0.9rem; letter-spacing: 2px; margin-bottom: 1.5rem;">
                IMAGE GALLERY
              </h3>
              <div class="items-list" style="display: flex; flex-direction: column; gap: 1rem;">
                <%= for img <- Enum.take(@images, 10) do %>
                  <div
                    class="writing-item"
                    style="padding: 1rem; min-height: auto; border-left: 2px solid #60a5fa; display: flex; flex-direction: row; align-items: center; gap: 1rem;"
                  >
                    <img
                      src={img.path}
                      style="width: 50px; height: 50px; object-fit: cover; border-radius: 6px; background: #222;"
                    />
                    <div class="item-main" style="flex: 1; min-width: 0;">
                      <h3
                        class="item-title"
                        style="font-size: 0.9rem; margin-bottom: 0.2rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;"
                      >
                        {img.name}
                      </h3>
                      <input
                        type="text"
                        value={"![img](#{img.path})"}
                        readonly
                        style="width: 100%; background: #000; border: 1px solid #333; color: #888; font-size: 0.7rem; padding: 0.2rem 0.5rem; border-radius: 4px;"
                        onclick="this.select(); document.execCommand('copy');"
                      />
                    </div>
                    <button
                      phx-click="delete_image"
                      phx-value-name={img.name}
                      class="icon-btn delete"
                      style="position: static; opacity: 1;"
                      phx-confirm="Purge?"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </div>
                <% end %>
              </div>
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
        .terminal-header { background: #151518; padding: 0.8rem 1.5rem; display: flex; align-items: center; border-bottom: 1px solid #1a1a1c; }
        .dots { display: flex; gap: 0.4rem; } .dots span { width: 8px; height: 8px; border-radius: 50%; background: #333; }
        .command-title { font-family: 'JetBrains Mono'; font-size: 0.7rem; color: #555; letter-spacing: 1px; }

        .terminal-body { padding: 4rem; min-height: 300px; transition: background 0.3s; }
        .drop-zone-master { background: rgba(255, 102, 0, 0.02); }
        .drop-zone-master[phx-drop-target] { cursor: copy; }

        .primary-pulse { animation: icon-wiggle 3s infinite; }
        @keyframes icon-wiggle { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-10px); } }

        .hidden-input { display: none; }
        .staged-queue { display: flex; flex-direction: column; gap: 1.2rem; }
        .staged-card { background: #000; border: 1px solid #111; padding: 1rem 1.5rem; border-radius: 10px; display: flex; justify-content: space-between; align-items: center; transition: all 0.3s; }
        .card-info { display: flex; align-items: center; gap: 1.5rem; flex: 1; min-width: 0; }
        .file-icon { font-size: 1.4rem; color: var(--accent-primary); }
        .file-details { flex: 1; display: flex; flex-direction: column; gap: 0.5rem; min-width: 0; }
        .file-name { font-family: 'JetBrains Mono'; font-size: 0.85rem; color: #fff; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .progress-wrap { height: 3px; background: #111; border-radius: 2px; overflow: hidden; width: 100%; max-width: 250px; }
        .progress-bar { height: 100%; background: var(--accent-primary); transition: width 0.3s; }

        .card-config { display: flex; align-items: center; gap: 1.5rem; }
        .minimal-select { background: #000; border: 1px solid #222; color: #888; border-radius: 6px; font-family: 'JetBrains Mono'; cursor: pointer; outline: none; }
        .minimal-select:focus { border-color: var(--accent-primary); color: #fff; }

        .launch-btn { background: #fff; color: #000; border: none; padding: 1rem 2.5rem; border-radius: 8px; font-weight: 900; font-size: 0.8rem; letter-spacing: 2px; position: relative; cursor: pointer; overflow: hidden; transition: all 0.3s; }
        .launch-btn:hover { transform: scale(1.02); }
        .btn-glow { position: absolute; inset: 0; background: linear-gradient(45deg, transparent, rgba(255,255,255,0.2), transparent); animation: sweep 2s infinite; }
        @keyframes sweep { 0% { transform: translateX(-100%); } 100% { transform: translateX(100%); } }

        .writing-item { background: #080808; border: 1px solid var(--border-color); border-radius: 12px; display: flex; flex-direction: column; position: relative; transition: all 0.3s; }
        .writing-item:hover { border-color: rgba(255, 102, 0, 0.3); background: #0c0c0e; }
        .item-type { font-size: 0.65rem; color: #444; margin-bottom: 0.5rem; letter-spacing: 2px; font-weight: 800; display: flex; align-items: center; gap: 0.6rem; }
        .item-title { font-size: 1.1rem; font-weight: 500; color: #fff; line-height: 1.25; }
        .item-meta { display: flex; align-items: center; justify-content: space-between; margin-top: auto; }
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
