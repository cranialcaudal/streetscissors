defmodule Web.Cuts do
  @moduledoc """
  The cutting room: a captain's log assembled from several takes, prints from
  the archive, titles and sound (`/admin/cuts`), the Premiere half of the
  admin's editing (`WebWeb.AdminLive.CuttingRoom`). His ask, 2026-10-17: logs
  "from several takes", "photos from the archive", "titles and music".

  **A cut renders into a captain's log, through the logs' own transcode.**
  `publish/2` has ffmpeg render the timeline (`Web.Cuts.Render`) to one MP4,
  stages it as a booth recording is staged, and makes a new log of it, or,
  when the cut was published before, gives that log the new source as
  `Web.Media.reencode/1` does. The transcoder then makes the 720p rendition
  and poster as for any log, and the log is published from `/admin/logs` as
  any other. The site's player, feed and pages need nothing new.

  **The bin is kept.** Unlike a booth recording, whose source is deleted once
  it has transcoded, a cut's takes and sounds stay in the cut's folder of the
  cutting room (beside the uploads root, which the proxy serves, never under
  it) until the cut is deleted, so a published log can be cut again. The
  browser plays a proxy of each (`make_proxy/1`: H.264 at 480 lines with a
  keyframe every half second, so scrubbing lands where it is put); the render
  reads the files as they came.

  Proxies and renders run in their own processes under `Web.TaskSupervisor`
  (inline in the suite, `:cuts_async`), and say what they did on the cut's
  topic (`subscribe/1`).
  """

  import Ecto.Query

  alias Web.Audio
  alias Web.Cuts.{Cut, Media, Render, Timeline, Titles}
  alias Web.Media.FFmpeg
  alias Web.Negatives
  alias Web.Repo
  alias Web.Uploads

  # ── Cuts ──────────────────────────────────────────────────────────────

  def list_cuts do
    Repo.all(from c in Cut, order_by: [desc: c.updated_at], preload: [:audio_log, :media])
  end

  def get_cut(id) do
    case Repo.get(Cut, id) do
      nil -> nil
      cut -> Repo.preload(cut, [:audio_log, :media])
    end
  end

  def create_cut(name) do
    with {:ok, cut} <-
           %Cut{}
           |> Cut.changeset(%{name: name, timeline: Timeline.empty()})
           |> Repo.insert() do
      {:ok, Repo.preload(cut, [:audio_log, :media])}
    end
  end

  def rename(%Cut{} = cut, name), do: cut |> Cut.changeset(%{name: name}) |> Repo.update()

  @doc "Deletes a cut and its bin. The log it made, if any, stays."
  def delete_cut(%Cut{} = cut) do
    with {:ok, cut} <- Repo.delete(cut) do
      File.rm_rf(bin(cut.id))
      {:ok, cut}
    end
  end

  @doc "The bin by id, ready or not."
  def media_by_id(%Cut{media: media}), do: Map.new(media, &{&1.id, &1})

  @doc "Saves a timeline, held to what the bin has (`Timeline.normalize/2`)."
  def save_timeline(%Cut{} = cut, timeline) do
    timeline = Timeline.normalize(timeline, media_by_id(cut))
    cut |> Cut.changeset(%{timeline: timeline}) |> Repo.update()
  end

  def subscribe(cut_id), do: Phoenix.PubSub.subscribe(Web.PubSub, topic(cut_id))
  defp topic(cut_id), do: "cut:#{cut_id}"
  defp tell(cut_id, message), do: Phoenix.PubSub.broadcast(Web.PubSub, topic(cut_id), message)

  # ── The bin ───────────────────────────────────────────────────────────

  @doc """
  A cut's folder: `cutting-room/<id>/` beside the uploads root. Beside, not
  under: everything under the uploads root is served to anyone by the proxy.
  """
  def bin(cut_id) do
    root = Uploads.root() |> Path.expand() |> Path.dirname()
    Path.join([root, "cutting-room", to_string(cut_id)])
  end

  def media_path(%Media{log_cut_id: cut_id, file: file}), do: Path.join(bin(cut_id), file)
  def proxy_path(%Media{proxy: nil}), do: nil
  def proxy_path(%Media{log_cut_id: cut_id, proxy: proxy}), do: Path.join(bin(cut_id), proxy)

  @doc """
  Takes an uploaded or recorded file into a cut's bin and makes its proxy.
  The file is moved (copied across filesystems), never read in place.
  """
  def add_media(%Cut{} = cut, source, client_name) do
    ext =
      client_name
      |> Path.extname()
      |> String.downcase()
      |> then(&if(&1 == "", do: ".bin", else: &1))

    name = client_name |> Path.basename() |> String.slice(0, 120)

    with {:ok, media} <-
           %Media{}
           |> Media.changeset(%{log_cut_id: cut.id, kind: "video", name: name, file: "pending"})
           |> Repo.insert() do
      file = "m#{media.id}#{ext}"
      File.mkdir_p!(bin(cut.id))
      target = Path.join(bin(cut.id), file)

      # Across filesystems a rename fails: copy, then let the original go.
      with {:error, _} <- File.rename(source, target) do
        File.cp!(source, target)
        File.rm(source)
      end

      {:ok, media} = media |> Media.changeset(%{file: file}) |> Repo.update()
      run(fn -> make_proxy(media) end)
      {:ok, media}
    end
  end

  @doc """
  Reads a file in the bin (its length, its shape, whether it has picture and
  sound) and makes the copy the browser plays. A file with a picture is a
  take; one without is a sound.
  """
  def make_proxy(%Media{} = media) do
    source = media_path(media)

    result =
      with {:ok, probe} <- FFmpeg.probe(source),
           true <- (probe.duration || 0) > 0 or {:error, "the file has no length"} do
        kind = if probe.has_video?, do: "video", else: "audio"
        proxy = "m#{media.id}.proxy" <> if(kind == "video", do: ".mp4", else: ".m4a")

        with :ok <- FFmpeg.run(proxy_args(kind, source, Path.join(bin(media.log_cut_id), proxy))) do
          {:ok,
           %{
             kind: kind,
             proxy: proxy,
             status: "ready",
             error: nil,
             duration_ms: round(probe.duration * 1000),
             width: probe.width,
             height: probe.height,
             has_audio: probe.has_audio?
           }}
        end
      end

    attrs =
      case result do
        {:ok, attrs} -> attrs
        {:error, reason} -> %{status: "failed", error: String.slice(to_string(reason), 0, 500)}
      end

    {:ok, media} = media |> Media.changeset(attrs) |> Repo.update()
    tell(media.log_cut_id, {:cut_media, media})
    {:ok, media}
  end

  defp proxy_args("video", source, output) do
    ["-i", source, "-map", "0:v:0", "-map", "0:a:0?"] ++
      ["-vf", "fps=30,scale=-2:480", "-c:v", "libx264", "-preset", "veryfast", "-crf", "26"] ++
      ["-pix_fmt", "yuv420p", "-g", "15", "-keyint_min", "15"] ++
      ["-c:a", "aac", "-b:a", "96k", "-ac", "2", "-movflags", "+faststart", output]
  end

  defp proxy_args("audio", source, output) do
    [
      "-i",
      source,
      "-vn",
      "-c:a",
      "aac",
      "-b:a",
      "128k",
      "-ac",
      "2",
      "-movflags",
      "+faststart",
      output
    ]
  end

  @doc "Takes a file out of the bin, and off the timeline."
  def remove_media(%Cut{} = cut, %Media{} = media) do
    File.rm(media_path(media))
    if media.proxy, do: File.rm(proxy_path(media))
    Repo.delete!(media)
    cut = get_cut(cut.id)
    save_timeline(cut, cut.timeline)
  end

  # ── Rendering ─────────────────────────────────────────────────────────

  @doc """
  Renders the cut and hands the film to the captain's logs. `attrs` gives a
  new log's `recorded_on` (today when absent). Runs in its own process; the
  cut's topic hears `{:cut_render, percent}` while it runs and
  `{:cut_rendered, cut}` or `{:cut_failed, cut}` when it ends.
  """
  def publish(%Cut{status: "rendering"}, _attrs), do: {:error, "this cut is rendering already"}

  def publish(%Cut{} = cut, attrs) do
    layout = Timeline.layout(cut.timeline)

    cond do
      layout.clips == [] ->
        {:error, "there is nothing on the main track to render"}

      Enum.any?(cut.media, &(&1.status == "processing")) ->
        {:error, "a file in the bin is still being read"}

      true ->
        {:ok, cut} =
          cut |> Cut.changeset(%{status: "rendering", render_error: nil}) |> Repo.update()

        run(fn -> render_and_hand_over(cut, layout, attrs) end)
        {:ok, cut}
    end
  end

  defp render_and_hand_over(cut, layout, attrs) do
    work = Path.join(bin(cut.id), "render")
    File.rm_rf(work)
    File.mkdir_p!(work)
    output = Path.join(work, "cut.mp4")

    result =
      with {:ok, files} <- files_for(cut, layout, work),
           :ok <- render(cut.id, Render.args(layout, files, output), layout.length),
           {:ok, log} <- hand_over(cut, output, attrs) do
        {:ok, log}
      end

    File.rm_rf(work)

    cut =
      case result do
        {:ok, log} ->
          Cut.changeset(cut, %{
            status: "done",
            audio_log_id: log.id,
            rendered_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })

        {:error, reason} ->
          Cut.changeset(cut, %{
            status: "failed",
            render_error: String.slice(to_string(reason), 0, 2000)
          })
      end
      |> Repo.update!()
      |> Repo.preload([:audio_log, :media], force: true)

    tell(cut.id, if(cut.status == "done", do: {:cut_rendered, cut}, else: {:cut_failed, cut}))
  end

  # Where every file the render reads is: the bin's files as they came, the
  # archive's prints, and the titles, set now.
  defp files_for(cut, layout, work) do
    media = Map.new(cut.media, &{&1.id, %{path: media_path(&1), has_audio: &1.has_audio}})

    stills =
      for %{"kind" => "still", "frame" => frame} <- layout.clips, into: %{} do
        [roll, number] = String.split(frame, "/")
        {frame, Negatives.frame_path(roll, number)}
      end

    titles =
      for title <- layout.titles, into: %{} do
        path = Path.join(work, "#{title["id"]}.png")
        {title["id"], {Titles.render(title, path), path}}
      end

    cond do
      Enum.find(stills, &match?({_, :error}, &1)) ->
        {frame, _} = Enum.find(stills, &match?({_, :error}, &1))
        {:error, "the print #{frame} is no longer in the archive"}

      Enum.find(titles, &match?({_, {{:error, _}, _}}, &1)) ->
        {_, {{:error, reason}, _}} = Enum.find(titles, &match?({_, {{:error, _}, _}}, &1))
        {:error, reason}

      true ->
        {:ok,
         %{
           media: media,
           stills: Map.new(stills, fn {frame, {:ok, path}} -> {frame, path} end),
           titles: Map.new(titles, fn {id, {:ok, path}} -> {id, path} end)
         }}
    end
  end

  # ffmpeg through a port, reading its -progress lines into a percentage.
  defp render(cut_id, args, total_ms) do
    {executable, argv} = FFmpeg.command(args)

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 65_536},
        args: argv
      ])

    collect(port, cut_id, total_ms, [], -1)
  end

  defp collect(port, cut_id, total_ms, tail, last) do
    receive do
      {^port, {:data, {_eol, "out_time_us=" <> us}}} ->
        percent =
          case Integer.parse(us) do
            {us, _} when total_ms > 0 -> min(round(us / 10 / total_ms), 99)
            _ -> last
          end

        if percent > last, do: tell(cut_id, {:cut_render, percent})
        collect(port, cut_id, total_ms, tail, max(percent, last))

      {^port, {:data, {_eol, line}}} ->
        collect(port, cut_id, total_ms, Enum.take([line | tail], 12), last)

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        {:error, "ffmpeg exited #{status}: " <> (tail |> Enum.reverse() |> Enum.join("\n"))}
    after
      3_600_000 -> {:error, "the render took more than an hour"}
    end
  end

  # The film becomes a log's source, exactly as a booth recording does.
  defp hand_over(cut, output, attrs) do
    source = Uploads.stage_upload!(output, "cut.mp4")

    case cut.audio_log_id && Audio.get_log(cut.audio_log_id) do
      %Audio.Log{} = log ->
        with {:ok, log} <-
               Audio.update_log(log, %{
                 source_path: source,
                 kind: "video",
                 trim_start_ms: nil,
                 trim_duration_ms: nil,
                 status: "pending",
                 transcode_error: nil
               }) do
          Web.Media.enqueue(log.id)
          {:ok, log}
        end

      _ ->
        recorded_on = attrs["recorded_on"] || Date.to_iso8601(Web.Clock.local_today())

        with {:ok, log} <-
               Audio.create_log(%{
                 "recorded_on" => recorded_on,
                 "kind" => "video",
                 "status" => "pending",
                 "source_path" => source,
                 "caption" => attrs["caption"],
                 "recorded_at" => DateTime.utc_now() |> DateTime.truncate(:second)
               }) do
          Web.Media.enqueue(log.id)
          {:ok, log}
        end
    end
    |> case do
      {:ok, log} ->
        {:ok, log}

      {:error, %Ecto.Changeset{} = changeset} ->
        Uploads.discard_staged(source)
        {:error, "the log could not be made: #{inspect(changeset.errors)}"}

      {:error, reason} ->
        Uploads.discard_staged(source)
        {:error, reason}
    end
  end

  # The suite runs these inline, where its sandboxed database can see them.
  defp run(fun) do
    if Application.get_env(:web, :cuts_async, true),
      do: Task.Supervisor.start_child(Web.TaskSupervisor, fun),
      else: fun.()

    :ok
  end
end
