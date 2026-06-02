defmodule WebWeb.AdminLive.ContentManager do
  use WebWeb, :live_view

  alias Web.Manuscripts
  alias Web.Audio

  def mount(params, session, socket) do
    if session["admin_user"] do
      # Manuscripts are mapped to the new streamlined categories
      legacy_categories = ["fiction", "reflections", "sensus", "physical", "faith", "non-fiction"]

      manuscripts =
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

      logs = Audio.list_logs()

      writing_categories = [
        "fitness intelligence",
        "latent sensus",
        "another blog"
      ]

      active_tab = Map.get(params, "tab", "writing")
      active_tab = if active_tab in ["writing", "audio"], do: active_tab, else: "writing"

      {:ok,
       assign(socket,
         page_title: "Control Center | Streetscissors",
         active_tab: active_tab,
         manuscripts: manuscripts,
         writing_categories: writing_categories,
         selected_category: "all",
         logs: logs,
         is_recording: false,
         editor_mode: nil,
         editing_item: nil,
         form_data: %{},
         grammar_matches: nil,
         sidebar_collapsed: false,

         # Per-file upload categories
         upload_categories: %{}
       )
       |> allow_upload(:markdown,
         accept: ~w(.md),
         max_entries: 20,
         max_file_size: 10_000_000
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  # --- Event Handlers (Grouped consecutively) ---

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab, editor_mode: nil)}
  end

  def handle_event("filter_category", %{"category" => category}, socket) do
    {:noreply, assign(socket, selected_category: category)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editor_mode: nil, editing_item: nil, grammar_matches: nil)}
  end

  def handle_event("edit_manuscript", %{"category" => cat, "slug" => slug}, socket) do
    case Manuscripts.get_manuscript(cat, slug) do
      {:ok, content} ->
        {:noreply,
         assign(socket,
           editor_mode: :edit_manuscript,
           form_data: %{
             "category" => cat,
             "slug" => slug,
             "content" => content,
             "original_slug" => slug
           }
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Manuscript lost in the void.")}
    end
  end

  def handle_event("save_manuscript", %{"manuscript" => params}, socket) do
    category = params["category"]
    slug = params["slug"]
    content = params["content"]
    Manuscripts.create_manuscript(category, slug, content)

    legacy_categories = ["fiction", "reflections", "sensus", "physical", "faith", "non-fiction"]

    manuscripts =
      Enum.flat_map(legacy_categories, fn legacy_cat ->
        Manuscripts.list_files(legacy_cat)
        |> Enum.map(fn m ->
          display_cat =
            case legacy_cat do
              "sensus" -> "latent sensus"
              "physical" -> "fitness intelligence"
              _ -> "another blog"
            end

          Map.put(m, :category, display_cat) |> Map.put(:category_folder, legacy_cat)
        end)
      end)

    {:noreply,
     socket
     |> put_flash(:info, "Manuscript scribed.")
     |> assign(editor_mode: nil, manuscripts: manuscripts)}
  end

  def handle_event("delete_manuscript", %{"category" => cat, "slug" => slug}, socket) do
    Manuscripts.delete_manuscript(cat, slug)
    legacy_categories = ["fiction", "reflections", "sensus", "physical", "faith", "non-fiction"]

    manuscripts =
      Enum.flat_map(legacy_categories, fn legacy_cat ->
        Manuscripts.list_files(legacy_cat)
        |> Enum.map(fn m ->
          display_cat =
            case legacy_cat do
              "sensus" -> "latent sensus"
              "physical" -> "fitness intelligence"
              _ -> "another blog"
            end

          Map.put(m, :category, display_cat) |> Map.put(:category_folder, legacy_cat)
        end)
      end)

    {:noreply, assign(socket, manuscripts: manuscripts) |> put_flash(:info, "Redacted.")}
  end

  def handle_event("validate_upload", %{"upload_categories" => cats}, socket) do
    # Update per-entry categories from the form
    {:noreply, assign(socket, upload_categories: cats)}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :markdown, ref)}
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

    legacy_categories = ["fiction", "reflections", "sensus", "physical", "faith", "non-fiction"]

    manuscripts =
      Enum.flat_map(legacy_categories, fn legacy_cat ->
        Manuscripts.list_files(legacy_cat)
        |> Enum.map(fn m ->
          display_cat =
            case legacy_cat do
              "sensus" -> "latent sensus"
              "physical" -> "fitness intelligence"
              _ -> "another blog"
            end

          Map.put(m, :category, display_cat) |> Map.put(:category_folder, legacy_cat)
        end)
      end)

    {:noreply,
     socket
     |> put_flash(:info, "Intel Ingested.")
     |> assign(manuscripts: manuscripts, upload_categories: %{})}
  end

  def handle_event("check_spelling", _params, socket) do
    content =
      if socket.assigns.editor_mode == :edit_manuscript do
        socket.assigns.form_data["content"]
      else
        nil
      end

    if content && content != "" do
      case Web.Language.Grammar.check(content) do
        {:ok, matches} -> {:noreply, assign(socket, grammar_matches: matches)}
        _ -> {:noreply, put_flash(socket, :error, "Heuristics failed.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Empty thoughts cannot be checked.")}
    end
  end

  def handle_event("dismiss_grammar", _params, socket) do
    {:noreply, assign(socket, grammar_matches: nil)}
  end

  def handle_event("save_audio_recording", params, socket) do
    %{"audio_data" => audio_data, "action" => action, "filename" => filename} = params
    is_published = action == "publish"
    binary_data = Base.decode64!(List.last(String.split(audio_data, ",")))

    uploads_dir = Path.join(["priv", "static", "uploads"])
    File.mkdir_p!(uploads_dir)
    webm_path = Path.join(uploads_dir, filename)
    File.write!(webm_path, binary_data)

    mp3_filename = String.replace(filename, ~r/\.webm$/i, ".mp3")
    mp3_path = Path.join(uploads_dir, mp3_filename)

    case System.cmd(
           "ffmpeg",
           [
             "-y",
             "-i",
             webm_path,
             "-vn",
             "-ar",
             "44100",
             "-ac",
             "2",
             "-codec:a",
             "libmp3lame",
             "-b:a",
             "192k",
             "-write_xing",
             "1",
             mp3_path
           ],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        File.rm(webm_path)
        stardate = calculate_stardate()
        web_path = "/uploads/#{mp3_filename}"

        case Audio.create_log(%{
               title: "Captain's Log #{stardate}",
               stardate: stardate,
               file_path: web_path,
               duration: 0,
               description: "Recorded from mission control.",
               published: is_published
             }) do
          {:ok, _log} ->
            {:noreply,
             socket
             |> put_flash(:info, "Broadcast archived.")
             |> assign(logs: Audio.list_logs())
             |> push_event("save_complete", %{success: true})}

          {:error, _} ->
            File.rm(mp3_path)
            {:noreply, put_flash(socket, :error, "Failed to archive.")}
        end

      {_, _} ->
        File.rm(webm_path)
        {:noreply, put_flash(socket, :error, "Conversion failure.")}
    end
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

  def handle_event("toggle_recording", _, socket) do
    {:noreply, assign(socket, :is_recording, !socket.assigns.is_recording)}
  end

  # --- Helpers ---

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
      <!-- Main Workspace -->
      <main class="workspace">
        <%= if @editor_mode do %>
          {render_editor(assigns)}
        <% else %>
          <header class="workspace-header">
            <div class="header-info">
              <h1 class="workspace-title">
                {if @active_tab == "writing", do: "Deep Writing", else: "Signal Broadcast"}
              </h1>
              <p class="workspace-subtitle">
                {if @active_tab == "writing",
                  do: "Drafting the future of intelligence.",
                  else: "Syncing frequencies with the collective."}
              </p>
            </div>

            <div class="header-actions" style="display: flex; gap: 0.5rem; align-items: center;">
              <button
                phx-click="switch_tab"
                phx-value-tab="writing"
                class={["action-btn", @active_tab == "writing" && "accent"]}
              >
                <i class="fas fa-pen-nib"></i> Writing Desk
              </button>
              <button
                phx-click="switch_tab"
                phx-value-tab="audio"
                class={["action-btn", @active_tab == "audio" && "accent"]}
              >
                <i class="fas fa-microphone-lines"></i> Audiologs
              </button>
              <%= if @active_tab == "audio" do %>
                <button phx-click="toggle_recording" class="action-btn accent">
                  <i class="fas fa-waveform"></i> Signal In
                </button>
              <% end %>
            </div>
          </header>

          <div
            class="workspace-content"
            phx-drop-target={if @active_tab == "writing", do: @uploads.markdown.ref}
          >
            <%= if @active_tab == "writing" do %>
              {render_writing_list(assigns)}
            <% else %>
              {render_audio_list(assigns)}
            <% end %>
          </div>
        <% end %>
      </main>
      
    <!-- Global Grammar Panel -->
      <WebWeb.CoreComponents.grammar_panel :if={@grammar_matches} matches={@grammar_matches} />

      <style>
        @import url('https://fonts.googleapis.com/css2?family=Outfit:wght@300;500;800&family=JetBrains+Mono:wght@400;700&display=swap');

        :root {
          --panel-bg: rgba(10, 10, 12, 0.98);
          --border-color: rgba(255, 255, 255, 0.08);
          --accent-primary: #ff6600;
          --accent-secondary: #00f2ff;
          --text-muted: #666;
          --sidebar-width: 240px;
          --glass-surface: rgba(255, 255, 255, 0.02);
        }

        .mission-control { display: flex; height: 100%; min-height: 80vh; background: #000; color: #fff; font-family: 'Outfit', sans-serif; overflow: hidden; }

        .command-sidebar { width: var(--sidebar-width); background: #050505; border-right: 1px solid var(--border-color); display: flex; flex-direction: column; padding: 2rem 1.2rem; }
        .sidebar-header { display: flex; align-items: center; gap: 1rem; margin-bottom: 4rem; }
        .logo-mini { background: #fff; color: #000; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; font-weight: 900; border-radius: 6px; }
        .logo-text { font-weight: 800; letter-spacing: 3px; font-size: 0.8rem; opacity: 0.9; }

        .sidebar-nav { flex: 1; display: flex; flex-direction: column; gap: 0.8rem; }
        .nav-item { display: flex; align-items: center; gap: 1.2rem; padding: 1rem 1.2rem; border-radius: 12px; color: #888; background: transparent; border: 1px solid transparent; cursor: pointer; transition: all 0.3s; font-size: 0.95rem; font-weight: 500; text-decoration: none; }
        .nav-item i { font-size: 1.1rem; opacity: 0.6; }
        .nav-item:hover { color: #fff; background: var(--glass-surface); border-color: rgba(255,255,255,0.05); }
        .nav-item.active { color: var(--accent-primary); background: rgba(255, 102, 0, 0.08); border-color: rgba(255, 102, 0, 0.2); }
        .nav-item.active i { opacity: 1; color: var(--accent-primary); }
        .nav-item.return-dash { margin-top: auto; border-top: 1px solid var(--border-color); padding-top: 2rem; border-radius: 0; }

        .workspace { flex: 1; display: flex; flex-direction: column; overflow: hidden; background: radial-gradient(circle at 70% 20%, rgba(255, 102, 0, 0.05), transparent 50%), #000; }
        .workspace-header { padding: 3rem 4rem; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid var(--border-color); }
        .workspace-title { font-size: 2.2rem; font-weight: 800; margin: 0; letter-spacing: -1px; background: linear-gradient(to bottom, #fff, #888); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .workspace-subtitle { color: #555; margin: 0.5rem 0 0 0; font-size: 1rem; }
        .action-btn { padding: 0.8rem 1.5rem; border-radius: 30px; font-weight: 800; cursor: pointer; border: 1px solid rgba(255,255,255,0.1); display: flex; align-items: center; gap: 0.8rem; transition: all 0.3s; font-size: 0.9rem; letter-spacing: 0.5px; }
        .action-btn.accent { background: var(--accent-primary); border: none; color: #fff; }
        .action-btn.accent:hover { transform: scale(1.02); box-shadow: 0 10px 30px rgba(255, 102, 0, 0.2); }
        .workspace-content { flex: 1; overflow-y: auto; padding: 3rem 4rem; position: relative; }

        ::-webkit-scrollbar { width: 10px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: #1a1a1a; border: 3px solid #000; border-radius: 10px; }
      </style>
    </div>
    """
  end

  defp render_writing_list(assigns) do
    ~H"""
    <div class="writing-grid">
      <!-- Sophisticated Ingestion Terminal -->
      <div class="ingestion-terminal">
        <form id="mkdn-upload-form" phx-change="validate_upload" phx-submit="ingest_files">
          <div class="terminal-shell">
            <div class="terminal-header">
              <div class="dots"><span></span><span></span><span></span></div>
              <div class="command-title">INGEST_INTELLIGENCE_V2.sh</div>
            </div>

            <div class="terminal-body">
              <div :if={Enum.empty?(@uploads.markdown.entries)} class="empty-state">
                <i class="fas fa-cloud-arrow-up primary-pulse"></i>
                <h3>STANDBY FOR INPUT</h3>
                <p>
                  Drag intelligence here or
                  <label class="action-link">
                    PICK FILES<.live_file_input upload={@uploads.markdown} class="hidden-input" />
                  </label>
                </p>
              </div>

              <div :if={!Enum.empty?(@uploads.markdown.entries)} class="staged-queue">
                <%= for entry <- @uploads.markdown.entries do %>
                  <div class="staged-card">
                    <div class="card-info">
                      <span class="file-icon"><i class="fas fa-file-lines"></i></span>
                      <div class="file-details">
                        <span class="file-name">{entry.client_name}</span>
                        <div class="progress-wrap">
                          <div class="progress-bar" style={"width: #{entry.progress}%"}></div>
                        </div>
                      </div>
                    </div>

                    <div class="card-config">
                      <div class="category-select">
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
                      </div>
                      <button
                        type="button"
                        phx-click="cancel_upload"
                        phx-value-ref={entry.ref}
                        class="purge-btn"
                      >
                        <i class="fas fa-trash"></i>
                      </button>
                    </div>
                  </div>
                <% end %>

                <div class="launch-sequence">
                  <button type="submit" class="launch-btn">
                    <span class="btn-text">
                      INITIALIZE COMMIT ({length(@uploads.markdown.entries)} UNITS)
                    </span>
                    <div class="btn-glow"></div>
                  </button>
                </div>
              </div>
            </div>
          </div>
        </form>
      </div>

      <div class="filters-bar">
        <div class="category-pills">
          <button
            phx-click="filter_category"
            phx-value-category="all"
            class={["pill", @selected_category == "all" && "active"]}
          >
            All
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

      <div class="items-list">
        <%= for man <- Enum.filter(@manuscripts, fn m -> @selected_category == "all" or m.category == @selected_category end) do %>
          <div class="writing-item manuscript">
            <div class="item-main">
              <div class="item-type"><i class="fas fa-scroll"></i> ARCHIVE</div>
              <h3 class="item-title">{man.title}</h3>
              <div class="item-meta">
                <span class="tag pill-sm">{man.category}</span>
                <span class="mtime">{Calendar.strftime(man.mtime, "%b %d")}</span>
              </div>
            </div>
            <div class="item-actions">
              <button
                phx-click="edit_manuscript"
                phx-value-category={man.category_folder}
                phx-value-slug={man.slug}
                class="icon-btn"
                title="Recall"
              >
                <i class="fas fa-edit"></i>
              </button>
              <button
                phx-click="delete_manuscript"
                phx-value-category={man.category_folder}
                phx-value-slug={man.slug}
                class="icon-btn delete"
                phx-confirm="Purge?"
              >
                <i class="fas fa-trash"></i>
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    <style>
      .writing-grid { display: flex; flex-direction: column; gap: 3rem; }

      .ingestion-terminal { max-width: 900px; margin: 0 auto 2rem; width: 100%; }
      .terminal-shell { background: #0a0a0c; border: 1px solid #1a1a1c; border-radius: 12px; overflow: hidden; box-shadow: 0 40px 100px rgba(0,0,0,0.8); }
      .terminal-header { background: #151518; padding: 0.8rem 1.2rem; display: flex; align-items: center; gap: 1.5rem; border-bottom: 1px solid #1a1a1c; }
      .dots { display: flex; gap: 0.4rem; }
      .dots span { width: 8px; height: 8px; border-radius: 50%; background: #333; }
      .command-title { font-family: 'JetBrains Mono'; font-size: 0.7rem; color: #555; letter-spacing: 1px; }

      .terminal-body { padding: 3rem; min-height: 240px; }
      .empty-state { display: flex; flex-direction: column; align-items: center; gap: 1.5rem; color: #444; }
      .primary-pulse { font-size: 3.5rem; animation: icon-wiggle 3s infinite; }
      @keyframes icon-wiggle { 0%, 100% { transform: translateY(0); color: #333; } 50% { transform: translateY(-10px); color: var(--accent-primary); } }
      .empty-state h3 { font-size: 1rem; font-weight: 800; letter-spacing: 4px; margin: 0; }
      .action-link { color: var(--accent-primary); cursor: pointer; text-decoration: underline; text-underline-offset: 4px; font-weight: 800; }
      .hidden-input { display: none; }

      .staged-queue { display: flex; flex-direction: column; gap: 1.2rem; }
      .staged-card { background: #000; border: 1px solid #111; padding: 1.5rem; border-radius: 10px; display: flex; justify-content: space-between; align-items: center; transition: all 0.3s; }
      .staged-card:hover { border-color: #222; }
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
      .launch-btn { background: #fff; color: #000; border: none; padding: 1.2rem 3rem; border-radius: 8px; font-weight: 900; font-size: 0.8rem; letter-spacing: 2px; position: relative; cursor: pointer; overflow: hidden; transition: all 0.3s; }
      .launch-btn:hover { transform: scale(1.02); }
      .btn-glow { position: absolute; inset: 0; background: linear-gradient(45deg, transparent, rgba(255,255,255,0.2), transparent); animation: sweep 2s infinite; }
      @keyframes sweep { 0% { transform: translateX(-100%); } 100% { transform: translateX(100%); } }

      .filters-bar { background: var(--glass-surface); padding: 1.2rem; border-radius: 20px; border: 1px solid var(--border-color); }
      .category-pills { display: flex; gap: 1rem; }
      .pill { padding: 0.6rem 1.5rem; border-radius: 30px; background: transparent; color: #666; cursor: pointer; border: 1px solid rgba(255,255,255,0.05); font-weight: 500; transition: all 0.3s; font-size: 0.9rem; }
      .pill.active { background: #fff; color: #000; border-color: #fff; transform: translateY(-2px); box-shadow: 0 10px 20px rgba(255,255,255,0.1); }
      .items-list { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 2rem; }
      .writing-item { background: #080808; border: 1px solid var(--border-color); border-radius: 20px; padding: 2.5rem; display: flex; flex-direction: column; min-height: 200px; position: relative; transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1); }
      .writing-item:hover { border-color: rgba(255, 102, 0, 0.3); transform: translateY(-8px); background: #0c0c0e; box-shadow: 0 30px 60px rgba(0,0,0,0.5); }
      .item-type { font-size: 0.7rem; color: #444; margin-bottom: 0.8rem; letter-spacing: 2px; font-weight: 800; display: flex; align-items: center; gap: 0.6rem; }
      .item-title { font-size: 1.4rem; font-weight: 500; margin: 0 0 1.5rem 0; color: #fff; line-height: 1.25; }
      .item-meta { display: flex; align-items: center; justify-content: space-between; margin-top: auto; border-top: 1px solid rgba(255,255,255,0.03); padding-top: 1.2rem; }
      .pill-sm { font-size: 0.7rem; color: #888; font-weight: 800; text-transform: uppercase; letter-spacing: 1px; }
      .mtime { font-size: 0.75rem; color: #333; }
      .item-actions { position: absolute; top: 1.5rem; right: 1.5rem; display: flex; gap: 0.8rem; opacity: 0; transition: opacity 0.3s; }
      .writing-item:hover .item-actions { opacity: 1; }
      .icon-btn { width: 36px; height: 36px; border-radius: 10px; background: #000; border: 1px solid #222; color: #666; cursor: pointer; transition: all 0.2s; display: flex; align-items: center; justify-content: center; font-size: 0.9rem; }
      .icon-btn:hover { color: #fff; border-color: #444; background: #111; }
      .icon-btn.delete:hover { border-color: #f00; color: #f00; }
    </style>
    """
  end

  defp render_audio_list(assigns) do
    ~H"""
    <div class="audio-studio">
      <%= if @is_recording do %>
        <div class="studio-console recording" id="audio-recorder" phx-hook="AudioRecorder">
          <div class="recording-visualizer">
            <div class="pulse-ring"></div>
            <i class="fas fa-microphone-alt"></i>
          </div>
          <h2 class="console-label">ENCRYPTING SIGNAL...</h2>
          <div id="recording-timer" class="timer">00:00</div>
          <div class="console-actions">
            <button phx-click="toggle_recording" class="action-btn">ABORT</button>
            <button id="stop-save" class="action-btn accent">COMMIT TO AETHER</button>
          </div>
        </div>
      <% end %>

      <div class="archives-grid">
        <%= for log <- @logs do %>
          <div class="archive-card">
            <div class="card-status-bar">
              <span class={["status-dot", log.published && "active"]}></span>
              <span class="stardate">{log.stardate}</span>
            </div>
            <h4 class="card-title">{log.title}</h4>
            <div class="player-container">
              <audio src={log.file_path} controls class="sc-player"></audio>
            </div>
            <div class="card-footer">
              <button phx-click="toggle_audio_status" phx-value-id={log.id} class="text-link">
                {if log.published, do: "CONCEAL", else: "BROADCAST"}
              </button>
              <button phx-click="delete_log" phx-value-id={log.id} class="text-link delete">
                PURGE
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_editor(assigns) do
    ~H"""
    <div class="full-screen-editor">
      <header class="editor-top-bar">
        <div class="meta">
          <span class="label">MS</span>
          <span class="title">
            {if @editing_item, do: Map.get(@editing_item, :title, "Conceptual Draft")}
          </span>
        </div>
        <div class="actions">
          <WebWeb.CoreComponents.grammar_button class="editor-btn" />
          <button phx-click="cancel_edit" class="editor-btn secondary">RETREAT</button>
          <button form="editor-form-ms" type="submit" class="editor-btn accent">COMMIT</button>
        </div>
      </header>

      <div class="editor-scaffold">
        <form id="editor-form-ms" phx-submit="save_manuscript">
          <div class="editor-controls">
            <div class="input-group">
              <label>IDENTIFIER</label>
              <input name="manuscript[slug]" value={@form_data["slug"]} class="sc-input" />
            </div>
            <div class="input-group">
              <label>FOLDER</label>
              <select name="manuscript[category]" class="sc-input">
                <%= for cat <- @writing_categories do %>
                  <option value={cat} selected={@form_data["category"] == cat}>{cat}</option>
                <% end %>
              </select>
            </div>
          </div>
          <div class="markdown-workspace">
            <textarea name="manuscript[content]" class="main-textarea"><%= @form_data["content"] %></textarea>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
