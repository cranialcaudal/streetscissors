defmodule Web.Fitness.Clip do
  @moduledoc """
  The film of a figure: the same loop `Web.Fitness.Figure` solves, drawn as a
  body in three dimensions with the muscles the exercise works lit, and kept
  as a short silent video.

  A phone should not have to build a body to show one, so the building is done
  once, here on the bench, and the page plays the result: `mix fitness.film`
  hands each figure's track (`Figure.track/2`) to the camera in
  `priv/figure/` (headless Chrome marching rays through the figure's shapes,
  piped to ffmpeg), and the page gets an H.264 loop of about a hundred
  kilobytes and its first frame as a poster.

  ## Where films live

  In `figures/` under the uploads root, which the proxy serves off disk:

      figures/
        clips.json                       what has been filmed, and from what
        goblet-squats-3fa91c0b72de.mp4   named by what is in it
        goblet-squats-3fa91c0b72de.jpg

  A film is named by a hash of its own bytes, so nothing at an address ever
  changes and the year-long cache header on `/uploads` is honest. `clips.json`
  maps each exercise to its film, to the `source` it was filmed from, and to
  what the page needs to play it (size, length, where each pose begins).

  ## A film is only shown for the figure it was filmed from

  `source/2` is a hash of the figure's file and the muscles lit. `find/2`
  answers only when the film's source is still the figure's, so a figure that
  has been edited since goes back to the flat drawing, which is always
  current, until it is filmed again; `unfilmed/0` lists those for
  `/admin/health`. A change to the camera's look does *not* retire a film: an
  older look is still a true picture of the exercise. Film everything again
  with `mix fitness.film --all`.

  ## The muscles

  `muscles/1` reads an exercise's `anatomy:` line into the camera's own
  seventeen volumes. It is the only place that vocabulary meets the wiki's
  free text.
  """

  alias Web.Fitness.{Figure, Vault}

  @subdir "figures"
  @manifest "clips.json"
  @fps 24

  # {what the anatomy line says, the camera's volume, how the page names it}
  @muscles [
    {~r/chest|pec(s|toral)/i, "chest", "Chest"},
    {~r/\blat(s|issimus)\b/i, "lats", "Lats"},
    {~r/trap|rhomboid|scapular|upper back|mid-back|thoracic/i, "traps", "Upper back"},
    {~r/delt|shoulder|rotator|infraspinatus|subscapularis|teres/i, "delts", "Shoulders"},
    {~r/bicep|brachialis\b/i, "biceps", "Biceps"},
    {~r/tricep/i, "triceps", "Triceps"},
    {~r/forearm|grip|brachioradialis|wrist|finger/i, "forearms", "Forearms"},
    {~r/rectus abdominis|transverse|abdominal|\babs\b|\bcore\b|hip flexor/i, "abs", "Abs"},
    {~r/oblique|quadratus/i, "obliques", "Obliques"},
    {~r/low(er)? back|erector|spinal|lumbar/i, "lowback", "Lower back"},
    {~r/glute|hip extensor|posterior chain|hip hinge/i, "glutes", "Glutes"},
    # "quadratus" is a muscle of the back, not the thigh
    {~r/\bquad(s|riceps)?\b/i, "quads", "Quads"},
    {~r/hamstring|posterior chain|hip hinge/i, "hamstrings", "Hamstrings"},
    {~r/cal(f|ves)\b|gastroc|soleus|achilles|ankle/i, "calves", "Calves"},
    {~r/adductor|groin/i, "adductors", "Adductors"},
    {~r/serratus/i, "serratus", "Serratus"}
  ]

  @doc "The camera's muscles an `anatomy:` line names, in the body's order from the chest down."
  def muscles(anatomy) when is_binary(anatomy) do
    for {said, muscle, _label} <- @muscles, Regex.match?(said, anatomy), do: muscle
  end

  def muscles(_anatomy), do: []

  @doc "What the page calls a muscle."
  def label(muscle) do
    case List.keyfind(@muscles, muscle, 1) do
      {_said, _muscle, label} -> label
      nil -> muscle
    end
  end

  @doc "The directory the films are kept in."
  def dir, do: Web.Uploads.dir(@subdir)

  @doc """
  What the figure's film is filmed from: its file as it stands and the
  muscles lit. `nil` when the exercise has no figure file.
  """
  def source(slug, anatomy) do
    case File.read(Figure.path(slug)) do
      {:ok, json} -> hash([json, 0, Enum.join(muscles(anatomy), ",")])
      {:error, _} -> nil
    end
  end

  @doc """
  The film of an exercise's figure, as the page plays it, or `nil` when there
  is none or the figure has changed since it was shot.

      %{video: "/uploads/figures/…mp4", poster: "/uploads/figures/…jpg",
        width: 720, height: 720, seconds: 3.4,
        stops: [%{name: "top", at: 0.0}, …], muscles: ["quads", …]}
  """
  def find(slug, anatomy) do
    with %{"file" => file, "source" => filmed} = entry <- Map.get(manifest(), slug),
         true <- filmed == source(slug, anatomy) do
      %{
        video: Web.Uploads.web_path(@subdir, file <> ".mp4"),
        poster: Web.Uploads.web_path(@subdir, file <> ".jpg"),
        width: entry["width"],
        height: entry["height"],
        seconds: entry["seconds"],
        stops: for(stop <- entry["stops"], do: %{name: stop["name"], at: stop["at"]}),
        muscles: entry["muscles"]
      }
    else
      _ -> nil
    end
  end

  @doc """
  Figures that draw and have no film of themselves as they now stand, by
  slug. Empty where nothing has ever been filmed: a site without films is
  not missing any.
  """
  def unfilmed do
    filmed = manifest()

    if filmed == %{} do
      []
    else
      for {slug, {:ok, _figure}} <- Figure.all(),
          Map.get(filmed, slug, %{})["source"] != source(slug, anatomy(slug)),
          do: slug
    end
  end

  # ── Filming ──────────────────────────────────────────────────────────

  @doc """
  Films figures and files the results. Options:

    * `:only` — slugs to consider (default: every figure in the vault);
    * `:all` — film even what already has a current film;
    * `:to` — the films' directory (default `dir/0`); the live site's is
      under its own uploads root, not the development one;
    * `:batch` — how many the camera takes at a time (default 6). The
      manifest is saved after each batch, so a long run cut short keeps what
      it finished;
    * `:say` — a function given a line about each figure as it is done.

  Returns `%{filmed: [slug], current: [slug], refused: [{slug, why}]}`.
  A figure that does not draw is refused, as the page refuses it.
  """
  def film(opts \\ []) do
    to = Keyword.get(opts, :to, dir())
    say = Keyword.get(opts, :say, fn _line -> :ok end)
    File.mkdir_p!(to)

    {jobs, current, refused} =
      opts
      |> Keyword.get(:only, all_slugs())
      |> Enum.reduce({[], [], []}, fn slug, {jobs, current, refused} ->
        case job(slug) do
          {:ok, job} ->
            if not Keyword.get(opts, :all, false) and filmed?(to, slug, job.source),
              do: {jobs, [slug | current], refused},
              else: {[job | jobs], current, refused}

          {:error, why} ->
            {jobs, current, [{slug, why} | refused]}
        end
      end)

    {filmed, failed} =
      jobs
      |> Enum.reverse()
      |> Enum.chunk_every(Keyword.get(opts, :batch, 6))
      |> Enum.reduce({[], []}, fn batch, {filmed, failed} ->
        case shoot(batch, to, say) do
          {:ok, slugs} -> {filmed ++ slugs, failed}
          {:error, why} -> {filmed, failed ++ for(job <- batch, do: {job.slug, why})}
        end
      end)

    %{filmed: filmed, current: Enum.reverse(current), refused: Enum.reverse(refused) ++ failed}
  end

  @doc """
  One picture of each pose of the given figures, as `<slug>-<n>.png` in `to`:
  what a figure is looked at with before it is filmed, since a file that
  draws is not thereby a picture of the exercise. Returns
  `{:ok, [path]}` or `{:error, why}`.
  """
  def stills(slugs, to) do
    File.mkdir_p!(to)
    jobs = for slug <- slugs, {:ok, job} <- [job(slug)], do: job
    list = Path.join(to, "jobs.json")

    File.write!(
      list,
      Jason.encode!(for(job <- jobs, do: Map.take(job, [:slug, :track, :muscles])))
    )

    {command, args} = camera()

    try do
      case System.cmd(command, args ++ [list, to, "--stills"], stderr_to_stdout: true) do
        {_output, 0} ->
          {:ok,
           for(
             job <- jobs,
             {_stop, n} <- Enum.with_index(job.track.stops),
             do: Path.join(to, "#{job.slug}-#{n}.png")
           )}

        {output, status} ->
          {:error, "the camera exited #{status}: #{String.trim(output)}"}
      end
    rescue
      error in ErlangError -> {:error, "could not run #{command}: #{inspect(error.original)}"}
    after
      File.rm(list)
    end
  end

  @doc "What the camera is given for one exercise: `{:ok, %{slug, source, track, muscles}}`."
  def job(slug) do
    anatomy = anatomy(slug)

    with {:ok, json} <- File.read(Figure.path(slug)),
         {:ok, %{} = raw} <- Jason.decode(json),
         {:ok, track} <- Figure.track(raw, @fps) do
      {:ok, %{slug: slug, source: source(slug, anatomy), track: track, muscles: muscles(anatomy)}}
    else
      {:error, problems} when is_list(problems) -> {:error, Enum.join(problems, "; ")}
      {:error, :enoent} -> {:error, "it has no figure file"}
      _ -> {:error, "its figure file is not a JSON object"}
    end
  end

  defp all_slugs, do: for({slug, _figure} <- Figure.all(), do: slug)

  defp anatomy(slug) do
    case Vault.get_exercise_by_slug(slug) do
      {:ok, exercise} -> exercise.anatomy
      _ -> nil
    end
  end

  defp filmed?(to, slug, source) do
    case Map.get(read_manifest(to), slug) do
      %{"source" => ^source, "file" => file} -> File.exists?(Path.join(to, file <> ".mp4"))
      _ -> false
    end
  end

  # One run of the camera: the batch's tracks in, a film and a poster each
  # out, into a scratch folder beside the films so the move into place is a
  # rename on the same disk.
  defp shoot(batch, to, say) do
    scratch = Path.join(to, ".filming-#{System.unique_integer([:positive])}")
    File.mkdir_p!(scratch)
    jobs = Path.join(scratch, "jobs.json")

    File.write!(
      jobs,
      Jason.encode!(for(job <- batch, do: Map.take(job, [:slug, :track, :muscles])))
    )

    {command, args} = camera()

    try do
      case System.cmd(command, args ++ [jobs, scratch], stderr_to_stdout: true) do
        {output, 0} ->
          shot =
            for line <- String.split(output, "\n"),
                {:ok, %{"slug" => _} = made} <- [Jason.decode(line)],
                do: made

          slugs =
            for made <- shot, job = Enum.find(batch, &(&1.slug == made["slug"])), job != nil do
              file(job, made, scratch, to)
              say.("#{job.slug}: #{made["width"]}×#{made["height"]}, #{made["frames"]} frames")
              job.slug
            end

          if length(slugs) == length(batch),
            do: {:ok, slugs},
            else:
              {:error,
               "the camera made #{length(slugs)} of #{length(batch)} films: #{String.trim(output)}"}

        {output, status} ->
          {:error, "the camera exited #{status}: #{String.trim(output)}"}
      end
    rescue
      error in ErlangError -> {:error, "could not run #{command}: #{inspect(error.original)}"}
    after
      File.rm_rf(scratch)
    end
  end

  # The camera is node running priv/figure/render.mjs; a test names a stub.
  defp camera do
    Application.get_env(:web, :figure_camera) ||
      {"node", [Application.app_dir(:web, "priv/figure/render.mjs")]}
  end

  # Moves a film into place under the name its bytes give it, records it, and
  # deletes the films it replaces.
  defp file(job, made, scratch, to) do
    film = Path.join(scratch, job.slug <> ".mp4")
    name = "#{job.slug}-#{film |> File.read!() |> hash()}"

    File.rename!(film, Path.join(to, name <> ".mp4"))
    File.rename!(Path.join(scratch, job.slug <> ".jpg"), Path.join(to, name <> ".jpg"))

    entry = %{
      "file" => name,
      "source" => job.source,
      "width" => made["width"],
      "height" => made["height"],
      "seconds" => job.track.seconds,
      "stops" => for(stop <- job.track.stops, do: %{"name" => stop.name, "at" => stop.at}),
      "muscles" => job.muscles
    }

    write_manifest(to, Map.put(read_manifest(to), job.slug, entry))

    earlier = ~r/^#{Regex.escape(job.slug)}-[0-9a-f]{12}\.(mp4|jpg)$/

    for old <- File.ls!(to), Regex.match?(earlier, old), Path.rootname(old) != name do
      File.rm(Path.join(to, old))
    end
  end

  # ── The manifest ─────────────────────────────────────────────────────

  # Read on every exercise page, so it is kept until the file changes.
  defp manifest do
    path = Path.join(dir(), @manifest)

    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime, size: size, inode: inode}} ->
        seen = {path, mtime, size, inode}

        case :persistent_term.get({__MODULE__, :manifest}, nil) do
          {^seen, filmed} ->
            filmed

          _ ->
            filmed = read_manifest(dir())
            :persistent_term.put({__MODULE__, :manifest}, {seen, filmed})
            filmed
        end

      {:error, _} ->
        %{}
    end
  end

  defp read_manifest(to) do
    with {:ok, json} <- File.read(Path.join(to, @manifest)),
         {:ok, %{} = filmed} <- Jason.decode(json) do
      filmed
    else
      _ -> %{}
    end
  end

  # Written beside and renamed over, so a page never reads half a manifest.
  # The rename gives it a new inode, which is how the site (another process)
  # sees a manifest rewritten within the second; this process just forgets.
  defp write_manifest(to, filmed) do
    path = Path.join(to, @manifest)
    File.write!(path <> ".new", Jason.encode!(filmed, pretty: true))
    File.rename!(path <> ".new", path)
    :persistent_term.erase({__MODULE__, :manifest})
  end

  defp hash(data) do
    :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower) |> binary_part(0, 12)
  end
end
