defmodule WebWeb.ArchiveLive do
  use WebWeb, :live_view

  @allowed_exts [".jpg", ".jpeg", ".png", ".webp", ".svg"]

  def mount(_params, _session, socket) do
    images = discover_images()

    if Enum.empty?(images) do
      {:ok,
       assign(socket,
         specimen: nil,
         total: 0,
         return_to: "/",
         return_label: "return to surface"
       )}
    else
      {:ok,
       assign(socket,
         images: images,
         specimen: Enum.random(images),
         total: length(images),
         return_to: "/",
         return_label: "return to surface"
       )}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="archive-container">
      <div class="archive-main">
        <%= if @specimen do %>
          <div class="archive-viewport">
            <div class="archive-specimen-meta">
              <span class="archive-filename">{@specimen.name}</span>
              <span class="archive-count">
                [ specimen {Enum.find_index(@images, &(&1 == @specimen)) + 1} of {@total} ]
              </span>
            </div>
            <img src={@specimen.url} class="archive-image" alt={@specimen.name} />
          </div>
        <% else %>
          <div class="archive-empty">
            <h2>No images found in archive.</h2>
            <p>Upload images to begin.</p>
          </div>
        <% end %>
      </div>

      <div class="archive-controls">
        <button phx-click="randomize" class="archive-btn">Randomize Specimen</button>
      </div>
    </div>
    """
  end

  def handle_event("randomize", _, socket) do
    {:noreply, assign(socket, specimen: Enum.random(socket.assigns.images))}
  end

  defp discover_images do
    base_dir = "priv/static/images"
    archive_dir = Path.join(base_dir, "archive")
    uploads_dir = Path.join(base_dir, "uploads")

    # Files in root images dir (excluding UI icons)
    root_images = scan_dir(base_dir, "/images/", true)

    # Files in archive subdir
    archive_images = scan_dir(archive_dir, "/images/archive/", false)

    # Files in uploads subdir
    upload_images = scan_dir(uploads_dir, "/images/uploads/", false)

    (root_images ++ archive_images ++ upload_images) |> Enum.uniq_by(& &1.url)
  end

  defp scan_dir(path, url_prefix, filter_ui) do
    if File.exists?(path) do
      File.ls!(path)
      |> Enum.filter(fn file ->
        ext = Path.extname(file) |> String.downcase()
        is_img = ext in @allowed_exts

        is_ui =
          if filter_ui do
            String.contains?(file, "_icon") or
              String.starts_with?(file, "logo") or
              String.starts_with?(file, "preview_logo")
          else
            false
          end

        is_img and not is_ui and not File.dir?(Path.join(path, file))
      end)
      |> Enum.map(fn file -> %{name: file, url: url_prefix <> file} end)
    else
      []
    end
  end
end
