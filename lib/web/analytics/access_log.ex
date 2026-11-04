defmodule Web.Analytics.AccessLog do
  @moduledoc """
  Caddy's access log, read as a stream of lines.

  Caddy writes one JSON object per request to `~/streetscissors-data/logs/`
  and rolls the file itself (100 MB a file, ten kept), gzipping the ones it
  rolls. Two things live in that log and nowhere else: the visitor's address
  (the database keeps only `Web.Analytics.hash_ip/1` of it) and the status
  the request got. Reader locations and the owner's own addresses are both
  recovered from it.

  **The rotations are most of the log.** Until 2026-10-31 the scan globbed
  `caddy_access*.log`, which matches the live file and none of the
  `caddy_access-2026-10-07T21-15-21.111.log.gz` rotations, so the window was
  the live file alone — five and a half days against seventy-eight. The glob
  here ends in `.log*` for that reason, and a `.gz` is inflated as it is read:
  the four files are ~250 MB unpacked, which is not something to hold in
  memory.

  A rotation Caddy is still writing can end mid-object, and a line can be
  half-written. Neither is remarkable, so a file that fails part-way through
  is skipped with what it had rather than failing the pass
  (`reduce_lines/3`).
  """

  require Logger

  @chunk 256 * 1024

  @doc "The access logs, newest last. `:dir` overrides the configured directory."
  def files(opts \\ []) do
    case Keyword.get_lazy(opts, :dir, &log_dir/0) do
      dir when is_binary(dir) ->
        if File.dir?(dir) do
          dir |> Path.join("caddy_access*.log*") |> Path.wildcard() |> Enum.sort()
        else
          []
        end

      _ ->
        []
    end
  end

  @doc """
  Folds `fun` over every line of every access log, oldest file first.

  The line is handed over raw: a caller that wants one field is better off
  testing the string before paying for `decode/1`, since the whole log is
  around 260,000 objects of 1.7 KB each.
  """
  def reduce_lines(acc, fun, opts \\ []) when is_function(fun, 2) do
    Enum.reduce(files(opts), acc, fn file, acc ->
      try do
        file |> stream() |> Enum.reduce(acc, fun)
      rescue
        error ->
          Logger.warning("access log #{Path.basename(file)} ended early: #{inspect(error)}")
          acc
      end
    end)
  end

  @doc "One log line as a map, or `nil` if it is not whole."
  def decode(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, %{} = entry} -> entry
      _ -> nil
    end
  end

  @doc """
  What the logs on disk can answer for: how many files, the earliest request
  in them, and how many distinct addresses they hold.
  """
  def coverage(opts \\ []) do
    {earliest, ips} =
      reduce_lines(
        {nil, MapSet.new()},
        fn line, {earliest, ips} ->
          # Two reads rather than one pattern across both: the order of the keys
          # in a line is Caddy's business, not something to depend on.
          at =
            case Regex.run(~r/"ts":\s*([0-9.]+)/, line) do
              [_, ts] -> ts |> Float.parse() |> elem(0)
              _ -> nil
            end

          ip =
            case Regex.run(~r/"client_ip":\s*"([^"]+)"/, line) do
              [_, ip] -> ip
              _ -> nil
            end

          {
            if(at, do: min(earliest || at, at), else: earliest),
            if(ip, do: MapSet.put(ips, ip), else: ips)
          }
        end,
        opts
      )

    %{
      files: length(files(opts)),
      earliest: earliest && DateTime.from_unix!(trunc(earliest)),
      ips: MapSet.size(ips)
    }
  end

  defp log_dir do
    Application.get_env(:web, :caddy_log_dir, Path.expand("~/streetscissors-data/logs"))
  end

  # A plain file is already line-oriented; a .gz is inflated chunk by chunk and
  # cut into lines afterwards, because a line straddles the chunks it arrives in.
  defp stream(path) do
    if String.ends_with?(path, ".gz") do
      path
      |> File.stream!([], @chunk)
      |> Stream.transform(&inflate_start/0, &inflate_chunk/2, &inflate_stop/1)
      |> lines()
    else
      File.stream!(path, [], :line)
    end
  end

  defp inflate_start do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z, 31)
    z
  end

  defp inflate_chunk(chunk, z), do: {[IO.iodata_to_binary(:zlib.inflate(z, chunk))], z}

  defp inflate_stop(z) do
    # inflateEnd raises when the stream never reached its end, which is exactly
    # what a rotation caught mid-write looks like. The handle still has to go.
    try do
      :zlib.inflateEnd(z)
    rescue
      _ -> :ok
    after
      :zlib.close(z)
    end
  end

  defp lines(stream) do
    stream
    |> Stream.concat([:eof])
    |> Stream.transform("", fn
      :eof, "" -> {[], ""}
      :eof, rest -> {[rest], ""}
      binary, rest -> split(rest <> binary)
    end)
  end

  defp split(buffer) do
    case String.split(buffer, "\n") do
      [only] -> {[], only}
      parts -> {Enum.drop(parts, -1), List.last(parts)}
    end
  end
end
