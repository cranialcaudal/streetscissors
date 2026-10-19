defmodule Web.Fitness.Changelog do
  @moduledoc """
  The regimen's history: `content/fitness/changelog.md`, one change to a
  heading and a short paragraph under it, newest anywhere in the file:

      ## 2026-10-26 — Get Sharp begins

      Eight weeks of double progression on the hinge and the press.

  Entries carry a date and never a time. Their titles are public (the
  homepage's "fitness update"); a missing file is no entries.
  """

  alias Web.Fitness.Vault

  @heading ~r/^##\s+(\d{4}-\d{2}-\d{2})\s+[—–-]\s+(.+?)\s*$/mu

  def path, do: Path.join(Vault.base_path(), "changelog.md")

  @doc "Every entry, newest first: `%{date, title, body}`, body as markdown."
  def entries do
    case File.read(path()) do
      {:ok, text} -> parse(text)
      {:error, _} -> []
    end
  end

  @doc "Entries dated on or before `date`: a change written ahead is not news yet."
  def entries_until(%Date{} = date),
    do: Enum.filter(entries(), &(Date.compare(&1.date, date) != :gt))

  @doc false
  def parse(text) do
    heads = Regex.scan(@heading, text, return: :index)

    heads
    |> Enum.with_index()
    |> Enum.flat_map(fn {[{start, len}, {d0, dl}, {t0, tl}], i} ->
      body_start = start + len

      body_end =
        case Enum.at(heads, i + 1) do
          [{next, _} | _] -> next
          nil -> byte_size(text)
        end

      with {:ok, date} <- Date.from_iso8601(binary_part(text, d0, dl)) do
        [
          %{
            date: date,
            title: binary_part(text, t0, tl),
            body: text |> binary_part(body_start, body_end - body_start) |> String.trim()
          }
        ]
      else
        _ -> []
      end
    end)
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end
end
