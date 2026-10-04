defmodule Web.Nearby do
  @moduledoc """
  What someone who landed on a missing page was probably looking for.

  A 404 that offers only "Return home" throws away the one thing it knows:
  the address that was asked for. That address nearly always says which
  section the visitor wanted and roughly what — a post whose file was renamed,
  a roll one number past the newest, a day with nothing on it. `suggest/1`
  reads it and answers with the nearest real things:

    * `/blog/<slug>` — the posts whose names are closest to that one
    * `/logs/<date>` — the recordings nearest that day
    * `/negatives/roll/<n>` (or `/archive/…`) — the rolls nearest that number
    * `/day/<date>` — the nearest days either side that have work on them
    * `/almanac/<year>` — the years there are
    * `/fitness/wiki/<slug>` — the exercises whose names are closest
    * `/<slug>`, one bare word — a post by that name, if one is close

  When a section is recognised and nothing in it is close, its newest work is
  offered instead, so the page is never a dead end.

  **Anything else gets nothing, on purpose.** Most 404s are not people. They
  are scanners asking for `/wp-login.php` and `/.env`, hundreds at a time,
  and reading the vault for each of those would let a stranger make the
  machine work for nothing. An address outside the site's own sections costs
  no file read and no query: the page shows the ways in and stops.

  Never raises. This runs while an error page is being drawn, and the one
  thing an error page must not do is fail.
  """

  alias Web.{Almanac, Audio, Blog, Keywords, Negatives}
  alias Web.Audio.Log
  alias Web.Fitness.Vault

  @limit 3
  # Jaro distance, 0..1. Below this two names share too little to be a typo
  # or a rename of each other.
  @close 0.72

  @type suggestion :: %{kind: String.t(), title: String.t(), path: String.t()}

  @doc "Up to three suggestions for a request path, nearest first."
  @spec suggest(String.t()) :: [suggestion()]
  def suggest(path) when is_binary(path) do
    path
    |> String.split("?")
    |> hd()
    |> String.split("/", trim: true)
    |> Enum.map(&URI.decode/1)
    |> near()
    |> Enum.take(@limit)
  rescue
    _ -> []
  end

  def suggest(_path), do: []

  defp near(["blog", slug | _]), do: similar_posts(slug) |> or_else(&newest_posts/0)
  defp near(["logs", slug | _]), do: logs_near(slug)

  defp near([section, "roll", roll | _]) when section in ["negatives", "archive"],
    do: rolls_near(roll)

  defp near(["negatives" | _]), do: rolls_near(nil)
  defp near(["day", date | _]), do: days_near(date)
  defp near(["almanac" | _]), do: years()
  defp near(["fitness", "wiki", slug | _]), do: similar_exercises(slug)

  # One bare word: an essay asked for without its /blog. Only a close match
  # is offered, and only for a word that could be a slug at all, which is
  # what keeps `/wp-login.php` from reading the vault.
  defp near([word]) do
    if Regex.match?(~r/\A[a-z0-9][a-z0-9-]{2,}\z/i, word), do: similar_posts(word, 0.85), else: []
  end

  defp near(_segments), do: []

  # --- Writing ---------------------------------------------------------------

  defp similar_posts(slug, threshold \\ @close) do
    wanted = Keywords.slugify(slug)

    Blog.list_posts()
    |> Enum.map(&{closeness(wanted, &1.slug), &1})
    |> Enum.filter(fn {score, _post} -> score >= threshold end)
    |> Enum.sort_by(fn {score, _post} -> -score end)
    |> Enum.map(fn {_score, post} -> post(post) end)
  end

  defp newest_posts, do: Enum.map(Blog.list_posts(), &post/1)

  defp post(post), do: %{kind: "Essay", title: post.title, path: "/blog/#{post.slug}"}

  # --- Recordings ------------------------------------------------------------

  # A log's address is its date, so a missing one names the day that was
  # wanted. Without a date in it, the newest are the best guess there is.
  defp logs_near(slug) do
    logs = Audio.list_ready_logs()

    case Date.from_iso8601(String.slice(slug, 0, 10)) do
      {:ok, date} -> Enum.sort_by(logs, &abs(Date.diff(&1.recorded_on, date)))
      _ -> logs
    end
    |> Enum.map(&%{kind: "Log", title: Log.title(&1), path: "/logs/#{&1.slug}"})
  end

  # --- The archive -----------------------------------------------------------

  defp rolls_near(roll) do
    sheets = Negatives.list_contact_sheets()

    case roll && Regex.run(~r/\d+/, roll) do
      [digits] ->
        number = String.to_integer(digits)
        Enum.sort_by(sheets, &abs(roll_number(&1) - number))

      _ ->
        sheets
    end
    |> Enum.map(fn sheet ->
      %{
        kind: "Roll",
        title: "Roll #{sheet.roll}, #{sheet.format}, #{sheet.date}",
        path: "/negatives/roll/#{sheet.roll}"
      }
    end)
  end

  defp roll_number(%{roll: roll}) do
    case Integer.parse(to_string(roll)) do
      {number, _} -> number
      :error -> 0
    end
  end

  # --- The almanac -----------------------------------------------------------

  defp days_near(text) do
    dates = Almanac.entries() |> Enum.map(& &1.date) |> Enum.uniq()

    case Date.from_iso8601(text) do
      {:ok, date} -> Enum.sort_by(dates, &abs(Date.diff(&1, date)))
      _ -> dates
    end
    |> Enum.map(fn date ->
      %{
        kind: "Day",
        title: Calendar.strftime(date, "%A, %-d %B %Y"),
        path: "/day/#{Date.to_iso8601(date)}"
      }
    end)
  end

  defp years do
    for year <- Almanac.years() do
      %{kind: "Year", title: "#{year}, the year at once", path: "/almanac/#{year}"}
    end
  end

  # --- The exercise wiki -----------------------------------------------------

  defp similar_exercises(slug) do
    wanted = Keywords.slugify(slug)

    for({_group, exercises} <- Vault.list_all_exercises(), exercise <- exercises, do: exercise)
    |> Enum.map(&{closeness(wanted, &1.slug), &1})
    |> Enum.filter(fn {score, _exercise} -> score >= @close end)
    |> Enum.sort_by(fn {score, _exercise} -> -score end)
    |> Enum.map(fn {_score, exercise} ->
      %{kind: "Exercise", title: exercise.name, path: "/fitness/wiki/#{exercise.slug}"}
    end)
  end

  # --- Shared ----------------------------------------------------------------

  # One name inside the other is a rename that kept its core
  # ("ferry" for "the-ferry-at-bowling-green"), which Jaro alone scores low.
  defp closeness(wanted, slug) do
    cond do
      wanted == "" -> 0.0
      String.contains?(slug, wanted) or String.contains?(wanted, slug) -> 0.95
      true -> String.jaro_distance(wanted, slug)
    end
  end

  defp or_else([], fallback), do: fallback.()
  defp or_else(found, _fallback), do: found
end
