defmodule Web.Fitness.Week do
  @moduledoc """
  The big-picture week: each day blocked into work and training around a fixed
  sleep window, read from `week.md` in the fitness vault.

  The file stays simple enough to read and edit in Obsidian:

      ---
      sleep: 21:00-05:30
      ---

      ## Monday
      - 06:30-07:10 strength Heavy Bag
      - 09:00-17:30 work Work

  Once parsed, every time is minutes past midnight. The timed view draws the
  waking day (wake-up to bedtime) unless the file sets its own `window:`;
  `sleep` is shaded wherever it overlaps that window.
  """

  alias Web.Fitness.Vault

  @kinds ~w[work swim bike run strength play stretch]a

  @default_sleep {21 * 60, 5 * 60 + 30}
  @default_window {5 * 60, 22 * 60}

  @doc "Reads and parses `week.md` from the fitness vault."
  def load do
    case File.read(Path.join(Vault.base_path(), "week.md")) do
      {:ok, content} -> {:ok, parse(content)}
      {:error, _} -> :error
    end
  end

  @doc """
  Parses the contents of `week.md` into
  `%{sleep: {bed, wake}, window: {from, to}, days: [%{slug, name, blocks}]}`.

  Blocks come back sorted by start. Lines that aren't blocks, and blocks that
  end before they start, are skipped; a kind outside #{inspect(@kinds)} becomes
  `:other` rather than dropping the block.
  """
  def parse(content) do
    {meta, body} = split_frontmatter(content)

    days =
      body
      |> String.split("\n")
      |> Enum.reduce([], &parse_line(String.trim(&1), &2))
      |> Enum.reverse()
      |> Enum.map(fn day -> %{day | blocks: day.blocks |> Enum.sort_by(& &1.start)} end)

    sleep = parse_range(meta["sleep"]) || @default_sleep

    %{
      sleep: sleep,
      window: parse_range(meta["window"]) || waking_hours(sleep),
      days: days
    }
  end

  # With no explicit window, the timed view draws the waking day — wake-up to
  # bedtime — so the full width of the screen goes to hours that hold blocks.
  defp waking_hours({bed, wake}) when bed > wake, do: {wake, bed}
  defp waking_hours(_sleep), do: @default_window

  @doc "How long the sleep window is, in minutes, allowing for it to wrap midnight."
  def sleep_minutes(%{sleep: {bed, wake}}) when bed > wake, do: 24 * 60 - bed + wake
  def sleep_minutes(%{sleep: {bed, wake}}), do: wake - bed

  @doc ~S'A block as a 12-hour clock span: `%{start: 435, stop: 1050}` -> "7:15–5:30".'
  def span(%{start: start, stop: stop}), do: "#{clock(start)}–#{clock(stop)}"

  @doc ~S'Minutes past midnight as a 12-hour clock time: 390 -> "6:30", 720 -> "12:00".'
  def clock(minutes) do
    hour = div(minutes, 60)
    minute = minutes |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{rem(hour + 11, 12) + 1}:#{minute}"
  end

  defp parse_line("## " <> name, days) do
    name = String.trim(name)
    [%{slug: String.downcase(name), name: name, blocks: []} | days]
  end

  defp parse_line(line, [day | rest] = days) do
    with [from, to, kind, label] <-
           Regex.run(~r/^-\s+(\d{1,2}:\d{2})\s*[-–]\s*(\d{1,2}:\d{2})\s+(\w+)\s+(.+)$/u, line,
             capture: :all_but_first
           ),
         start when is_integer(start) <- minutes(from),
         stop when is_integer(stop) and stop > start <- minutes(to) do
      block = %{start: start, stop: stop, kind: kind(kind), label: String.trim(label)}
      [%{day | blocks: [block | day.blocks]} | rest]
    else
      _ -> days
    end
  end

  defp parse_line(_line, days), do: days

  defp kind(name) do
    name = String.downcase(name)
    Enum.find(@kinds, :other, &(Atom.to_string(&1) == name))
  end

  defp parse_range(nil), do: nil

  defp parse_range(value) do
    with [from, to] <- String.split(value, "-", parts: 2),
         start when is_integer(start) <- minutes(from),
         stop when is_integer(stop) <- minutes(to) do
      {start, stop}
    else
      _ -> nil
    end
  end

  defp minutes(hhmm) do
    with [h, m] <- hhmm |> String.trim() |> String.split(":"),
         {h, ""} <- Integer.parse(h),
         {m, ""} <- Integer.parse(m),
         true <- h in 0..24 and m in 0..59 do
      h * 60 + m
    else
      _ -> nil
    end
  end

  # Same flat `key: value` frontmatter the rest of the vault uses. Splitting on
  # the first ": " keeps a value like `21:00-05:30` whole.
  defp split_frontmatter(content) do
    case Regex.run(~r/\A---\n(.*?)\n---\n?(.*)\z/s, content, capture: :all_but_first) do
      [yaml, body] ->
        meta =
          yaml
          |> String.split("\n")
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(line, ": ", parts: 2) do
              [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
              _ -> acc
            end
          end)

        {meta, body}

      _ ->
        {%{}, content}
    end
  end
end
