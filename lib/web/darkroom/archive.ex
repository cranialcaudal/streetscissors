defmodule Web.Darkroom.Archive do
  @moduledoc """
  The prints of the whole archive, measured (`Web.Darkroom.Stats`) and grouped
  by film, for what a film looks like on average in the author's own hands:
  the `m` of `Web.Darkroom.Prior`.

  **A print is grouped by its stock** when its roll names one
  (`roll.json`'s `film`, matched by `Web.Darkroom.Film.match/1`), and
  otherwise by its process (`C-41`, `E-6` or `BW`, from the roll's colour and
  whether `film-develop` read it as slide). What is measured is the print as
  developed (`Darkroom.source_path/2`), never an edit of it, so a group's
  average is the film's and not the author's taste.

  Measurements are kept in `<archive>/.darkroom/stats.json` by print and file
  time, so only a new or redeveloped print is read again.
  """

  alias Web.Darkroom
  alias Web.Darkroom.{Film, Stats}
  alias Web.Negatives
  alias Web.Negatives.RollMeta

  defp cache_path, do: Path.join([Negatives.base_path(), ".darkroom", "stats.json"])

  @doc "Every print: `%{roll, frame, dir, group, stock, stats}`."
  def prints do
    cache = read_cache()

    {prints, cache} =
      Enum.flat_map_reduce(rolls(), cache, fn roll, cache ->
        Enum.map_reduce(Negatives.list_frames(roll.roll), cache, fn %{frame: frame}, cache ->
          source = Darkroom.source_path(roll.dir, frame)
          key = "#{roll.roll}/#{frame}"
          mtime = mtime(source)

          {stats, cache} =
            case cache[key] do
              %{"mtime" => ^mtime, "stats" => stats} ->
                {decode(stats), cache}

              _ ->
                case Stats.read(source) do
                  {:ok, stats} ->
                    {stats, Map.put(cache, key, %{"mtime" => mtime, "stats" => encode(stats)})}

                  :error ->
                    {nil, cache}
                end
            end

          {%{
             roll: roll.roll,
             frame: frame,
             dir: roll.dir,
             group: roll.group,
             stock: roll.stock,
             stats: stats
           }, cache}
        end)
      end)

    write_cache(cache)
    Enum.filter(prints, & &1.stats)
  end

  @doc "A roll's group and stock: `{group, stock or nil}`."
  def group_of(roll_dir, color) do
    stock = Film.match(RollMeta.read(roll_dir).film)

    group =
      cond do
        stock -> stock["id"]
        color == "bw" -> "BW"
        slide?(roll_dir) -> "E-6"
        true -> "C-41"
      end

    {group, stock}
  end

  @doc """
  What each group looks like on average: `%{group => %{n, cast: {rg, bg},
  var: {var_rg, var_bg}}}`, over its prints with enough neutral in them to
  say.
  """
  def groups(prints \\ prints()) do
    prints
    |> Enum.filter(&(&1.stats.neutral >= 0.05))
    |> Enum.group_by(& &1.group)
    |> Map.new(fn {group, list} ->
      rgs = Enum.map(list, &elem(&1.stats.cast, 0))
      bgs = Enum.map(list, &elem(&1.stats.cast, 1))
      {group, %{n: length(list), cast: {mean(rgs), mean(bgs)}, var: {var(rgs), var(bgs)}}}
    end)
  end

  defp rolls do
    for sheet <- Negatives.list_contact_sheets(),
        {:ok, dir} <- [Negatives.roll_dir(sheet.roll)] do
      {group, stock} = group_of(dir, sheet.color)
      %{roll: sheet.roll, dir: dir, group: group, stock: stock}
    end
  end

  defp slide?(roll_dir) do
    with {:ok, body} <- File.read(Path.join(roll_dir, "frames.json")),
         {:ok, %{"mode" => "slide"}} <- Jason.decode(body) do
      true
    else
      _ -> false
    end
  end

  defp mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: t}} -> t
      _ -> 0
    end
  end

  defp read_cache do
    with {:ok, body} <- File.read(cache_path()),
         {:ok, %{} = cache} <- Jason.decode(body) do
      cache
    else
      _ -> %{}
    end
  end

  defp write_cache(cache) do
    path = cache_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path <> ".partial", Jason.encode_to_iodata!(cache))
    File.rename!(path <> ".partial", path)
  end

  defp encode(%{cast: {rg, bg}} = stats),
    do: stats |> Map.put(:cast, [rg, bg]) |> Map.new(fn {k, v} -> {to_string(k), v} end)

  defp decode(map) do
    stats = Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
    %{stats | cast: List.to_tuple(stats.cast)}
  end

  defp mean([]), do: 0.0
  defp mean(list), do: Enum.sum(list) / length(list)

  defp var(list) when length(list) < 2, do: 0.0

  defp var(list) do
    m = mean(list)
    Enum.sum(Enum.map(list, &((&1 - m) * (&1 - m)))) / (length(list) - 1)
  end
end
