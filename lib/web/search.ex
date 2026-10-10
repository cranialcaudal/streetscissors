defmodule Web.Search do
  @moduledoc """
  One search across the whole site, answered section by section.

  There is no index to keep in step with the content: each query reads the
  same list functions the pages themselves read, because the whole corpus is
  a few hundred files and rows. `search/1` answers
  `[%{section, results: [%{title, path, context}]}]`, sections in the order
  below and only the ones that found something:

    * **Pages** — every page that is a place rather than a piece: the
      sections, each day of the regimen, each year of the daybook, the hours
      and the Rosary (`pages/0`)
    * **Blog** — title, keywords, then the body (the matching line is the context)
    * **Captain's logs** — the day it was recorded, caption, description, keywords
    * **Exercise wiki** — name, muscle group, anatomy, category, then the body
    * **Activities** — every Komoot tour `/fitness/rides` lists, by name, by
      sport in plain words (`bike`, `cycling`, `run`, `hike`), by `komoot`,
      and by month and year (`july 2026`)
    * **Photographs** — a roll by number (`7`, `007`, `roll7`), date, format, film,
      and after the rolls each finished print (`roll 7 frame 3`)
    * **Saints** — by name
    * **The Bible** — a book by name, or a typed citation (`John 3:16`)
    * **How it works** — the manual's headings

  Every word of the query has to appear, as a word or the start of one
  (`pull` finds "Pull-Ups", not "controlled"). Within a section a name that *is*
  the query leads, then names that begin with it, then names that contain
  it, then everything found only in the text.

  **Every page is in here, always.** A page with no content of its own to
  list goes in `pages/0`, and `test/web/search_test.exs` walks the router and
  fails when a public address is in neither that list nor a section above,
  so a new page cannot be added without being made findable. The two
  deliberately unlisted pages (`/food`, `/england2026`) are the only ones
  held back, named in `unlisted/0`.

  Drafts and unpublished logs are never read: every source here is the
  public list function. A source that is missing (the negatives volume is
  outside the checkout) answers nothing rather than raising.
  """

  alias Web.{Audio, Bible, Blog, Negatives, Rides}
  alias Web.Audio.Log
  alias Web.Bible.Citation
  alias Web.Fitness.Vault
  alias Web.Liturgy.Saints

  @min 2
  @max 80
  @per_section 12
  @manual "docs/how-to.md"

  # Where the rest of a section is, for when it found more than it shows.
  @section_pages %{
    "Blog" => "/blog",
    "Captain's logs" => "/logs",
    "Exercise wiki" => "/fitness/wiki",
    "Activities" => "/fitness/rides",
    "Photographs" => "/negatives",
    "The Bible" => "/Christ/bible",
    "How it works" => "/how-to"
  }

  @type result :: %{title: String.t(), path: String.t(), context: String.t() | nil}
  @type group :: %{section: String.t(), results: [result()], more: non_neg_integer()}

  @doc "The query as it will be searched: trimmed, single-spaced, cut to #{@max} characters."
  @spec clean(term()) :: String.t()
  def clean(query) when is_binary(query) do
    query |> String.replace(~r/\s+/u, " ") |> String.trim() |> String.slice(0, @max)
  end

  def clean(_query), do: ""

  @doc "Whether a cleaned query is long enough to be worth searching for."
  def searchable?(query), do: String.length(clean(query)) >= @min

  @doc """
  Everything on the site matching `query`, grouped by section. `more` is how
  many further matches a section had beyond the #{@per_section} it shows.
  """
  @spec search(term()) :: [group()]
  def search(query) do
    q = query |> clean() |> String.downcase()

    if String.length(q) < @min do
      []
    else
      words = q |> fold() |> String.split(" ", trim: true)

      for {section, source} <- sources(),
          found = safe(fn -> source.(q, words, true) end),
          found != [] do
        ranked =
          found
          |> Enum.sort_by(&{&1.rank, &1.order})
          |> Enum.map(&Map.take(&1, [:title, :path, :context]))

        %{
          section: section,
          results: Enum.take(ranked, @per_section),
          more: max(length(ranked) - @per_section, 0),
          all: @section_pages[section]
        }
      end
    end
  end

  @suggestions 8

  @doc """
  What to offer while a query is still being typed: the #{@suggestions} nearest
  things by **name** across every section, as `[%{title, path, section}]`,
  nearest first. Nothing's text is read (this runs on each pause in typing),
  so a suggestion is always something whose name, keywords or other fields
  match; the full search is what finds a word inside a post.
  """
  @spec suggest(term()) :: [%{title: String.t(), path: String.t(), section: String.t()}]
  def suggest(query) do
    q = query |> clean() |> String.downcase()
    words = q |> fold() |> String.split(" ", trim: true)

    if String.length(q) < @min or words == [] do
      []
    else
      found =
        for {{section, source}, at} <- Enum.with_index(sources()),
            entry <- safe(fn -> source.(q, words, false) end) do
          {{entry.rank, at, entry.order},
           %{title: entry.title, path: entry.path, section: section}}
        end

      found
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq_by(& &1.path)
      |> Enum.take(@suggestions)
    end
  end

  defp sources do
    [
      {"Pages", &pages/3},
      {"Blog", &posts/3},
      {"Captain's logs", &logs/3},
      {"Exercise wiki", &exercises/3},
      {"Activities", &rides/3},
      {"Photographs", &rolls/3},
      {"Saints", &saints/3},
      {"The Bible", &bible/3},
      {"How it works", &manual/3}
    ]
  end

  # ── Pages ─────────────────────────────────────────────────────────

  # {title, path, what it is, other words someone might type for it}
  @fixed [
    {"Home", "/", "The front door", "homepage start streetscissors"},
    {"Blog", "/blog", "Essays and written work", "writing posts essays manuscripts"},
    {"Captain's Logs", "/logs", "Recordings, video and audio", "audio video recordings spoken"},
    {"Contact Sheets / Photos", "/negatives", "Every roll of film",
     "negatives photographs film archive rolls darkroom pictures"},
    {"Fitness & Sport", "/fitness", "Today's training", "regimen workout gym training today"},
    {"Exercise Wiki", "/fitness/wiki", "Every exercise, by muscle group", "exercises movements"},
    {"Activities", "/fitness/rides", "Rides, runs and swims recorded on Komoot",
     "rides runs cycling komoot gps"},
    {"About Me", "/about", "Who made this", "author bio"},
    {"How It Works", "/how-to", "The manual", "manual documentation help guide"},
    {"Roadmap", "/roadmap", "What gets built next", "plan plans future"},
    {"The Daybook", "/daybook", "This week, and everything made, day by day",
     "almanac calendar week diary engagement history years archive"},
    {"Guestbook", "/guestbook", "Sign it", "sign messages visitors"},
    {"Newsletter", "/newsletter", "Posts by mail", "subscribe email mailing list"},
    {"Contact", "/contact", "Write to me", "email message write letter"},
    {"The PC", "/pc", "A terminal that knows the site by filename",
     "terminal dos command prompt"},
    {"Feed", "/feed", "RSS", "rss atom subscribe reader"},
    {"Search", "/search", "This page", "find"},
    {"Christ", "/Christ", "The day's prayer",
     "prayer faith today liturgy mass catholic carmelite"},
    {"Morning Prayer", "/Christ/hours/lauds", "Lauds", "lauds office hours liturgy"},
    {"Evening Prayer", "/Christ/hours/vespers", "Vespers", "vespers office hours liturgy"},
    {"Night Prayer", "/Christ/hours/compline", "Compline", "compline office hours liturgy"},
    {"The Angelus", "/Christ/angelus", "At noon", "regina caeli midday noon"},
    {"Readings at Mass", "/Christ/readings", "Today's readings", "gospel lectionary scripture"},
    {"The Rosary", "/Christ/rosary", "Today's mysteries, bead by bead",
     "mysteries beads hail mary"},
    {"The Liturgical Calendar", "/Christ/calendar", "A month of days",
     "saints feasts month ordo seasons"},
    {"The Bible", "/Christ/bible", "Every book", "scripture books testament"}
  ]

  @unlisted ["/food", "/england2026", "/england2026/call"]

  @doc """
  The pages that are deliberately off every list on the site, and so off this
  one. Moving an address out of here and into `@fixed` is all it takes.
  """
  def unlisted, do: @unlisted

  @doc """
  Every page that is a place rather than a piece of work, as
  `[%{title, path, context, words}]`: the fixed ones above, then the ones
  the content decides (a day of the regimen, a year of the daybook, a set of
  mysteries).
  """
  def pages do
    fixed =
      for {title, path, context, words} <- @fixed,
          do: %{title: title, path: path, context: context, words: words <> named(path)}

    fixed ++ safe(&regimen_days/0) ++ safe(&almanac_years/0) ++ rosary_sets()
  end

  # The author's page is also found by the author's name, which is the
  # host's to say (`AUTHOR_NAME`), never the code's.
  defp named("/about") do
    case Application.get_env(:web, :author_name) do
      name when is_binary(name) and name != "" -> " " <> String.downcase(name)
      _ -> ""
    end
  end

  defp named(_path), do: ""

  defp regimen_days do
    for day <- Vault.list_days(),
        day.slug in ~w(monday tuesday wednesday thursday friday saturday sunday) do
      %{
        title: day.title,
        path: "/fitness/day/#{day.slug}",
        context: "The regimen, #{String.capitalize(day.slug)}",
        words: "#{day.slug} #{day.theme} #{day.description} fitness regimen workout"
      }
    end
  end

  defp almanac_years do
    for year <- Web.Almanac.years() do
      %{
        title: "The Daybook, #{year}",
        path: "/daybook/#{year}",
        context: "The year, month by month",
        words: "year"
      }
    end
  end

  defp rosary_sets do
    for key <- Web.Liturgy.Rosary.keys(), set = Web.Liturgy.Rosary.set(key) do
      %{
        title: set.title,
        path: "/Christ/rosary?set=#{key}",
        context: "The Rosary",
        words: Enum.map_join(set.mysteries, " ", & &1.title)
      }
    end
  end

  defp pages(q, words, _deep) do
    for {page, order} <- Enum.with_index(pages()),
        hit = hit(q, words, page.title, [page.context, page.words], nil) do
      entry(hit, order, page.title, page.path, page.context)
    end
  end

  # ── Sources ───────────────────────────────────────────────────────

  defp posts(q, words, deep) do
    for {post, order} <- Enum.with_index(Blog.list_posts()),
        hit = hit(q, words, post.title, post.keywords, deep && fn -> post_body(post.slug) end) do
      entry(hit, order, post.title, "/blog/#{post.slug}", Date.to_iso8601(post.date))
    end
  end

  defp post_body(slug) do
    case Blog.get_post(slug) do
      {:ok, post} -> post.body || ""
      _ -> ""
    end
  end

  defp logs(q, words, deep) do
    for {log, order} <- Enum.with_index(Audio.list_ready_logs()),
        title = Log.title(log),
        fields = [log.slug, log.caption | Log.keyword_list(log)],
        hit = hit(q, words, title, fields, deep && fn -> log.description || "" end) do
      entry(hit, order, title, "/logs/#{log.slug}", log.caption)
    end
  end

  defp exercises(q, words, deep) do
    for {_group, list} <- Vault.list_all_exercises(),
        exercise <- list,
        fields = [
          exercise.muscle_group,
          exercise.anatomy,
          exercise.functional_category,
          exercise.short_description
        ],
        hit = hit(q, words, exercise.name, fields, deep && fn -> exercise_body(exercise.slug) end) do
      entry(
        hit,
        exercise.name,
        exercise.name,
        "/fitness/wiki/#{exercise.slug}",
        exercise.muscle_group && String.capitalize(to_string(exercise.muscle_group))
      )
    end
  end

  defp exercise_body(slug) do
    case Vault.get_exercise_raw(slug) do
      {:ok, _exercise, body} -> body
      _ -> ""
    end
  end

  # Komoot names most tours "Ride" or "Run", and its own word for a sport is
  # "touringbicycle", so a ride is found by more than its name: what the
  # sport is called here, the words people use for it, "komoot" itself, and
  # the month and year it was on. What it shows is what tells two rides
  # called "Ride" apart: the sport, the distance and the day.
  defp rides(q, words, _deep) do
    for {ride, order} <- Enum.with_index(Rides.list_rides()),
        title = ride.name || "Activity",
        day = ride.started_at && Web.Clock.local_today(ride.started_at),
        sport = Rides.Units.sport(ride.sport),
        fields = [
          sport,
          ride_words(Rides.Units.sport_kind(ride.sport)),
          "komoot activity activities",
          day && Calendar.strftime(day, "%B %Y %-d %b"),
          day && Date.to_iso8601(day)
        ],
        hit = hit(q, words, title, fields, nil) do
      context =
        [sport, Rides.Units.distance(ride.distance_m), day && Calendar.strftime(day, "%-d %B %Y")]
        |> Enum.reject(&(&1 in [nil, false]))
        |> Enum.join(" · ")

      entry(hit, order, title, "/fitness/rides/#{ride.id}", context)
    end
  end

  defp ride_words("bike"), do: "bike bicycle biking cycling cycle ride rides"
  defp ride_words("run"), do: "run runs running jog jogging"
  defp ride_words("hike"), do: "hike hikes hiking walk walking"
  defp ride_words(_other), do: ""

  # Rolls first, then each roll's finished prints: a frame is a page too,
  # found the way it is said ("roll 7 frame 3") or through its roll's film.
  defp rolls(q, words, _deep) do
    sheets = Enum.with_index(Negatives.list_contact_sheets())

    rolls =
      for {sheet, order} <- sheets,
          title = "Roll #{pad(sheet.roll_num)}",
          fields = [sheet.slug, sheet.date, sheet.format, sheet.color],
          hit = (roll?(sheet, q) && 0) || hit(q, words, title, fields, nil) do
        context = "#{sheet.date} · #{sheet.format} · #{sheet.color} · #{sheet.frames} frames"
        entry(hit, {0, order, 0}, title, "/negatives/roll/#{pad(sheet.roll_num)}", context)
      end

    frames =
      for {sheet, order} <- sheets,
          %{frame: frame} <- sheet.roll |> Negatives.list_frames() |> Enum.sort_by(& &1.frame),
          title = "Roll #{pad(sheet.roll_num)}, frame #{frame}",
          fields = [sheet.roll_num, sheet.slug, sheet.date, sheet.format, sheet.color, "print"],
          hit = hit(q, words, title, fields, nil) do
        context = "A finished print · #{sheet.date} · #{sheet.format} · #{sheet.color}"
        path = "/negatives/roll/#{pad(sheet.roll_num)}/frame/#{frame}"
        # Never ahead of a roll: a frame's name begins with its roll's.
        entry(max(hit, 2), {1, order, frame}, title, path, context)
      end

    rolls ++ frames
  end

  # A roll the way a person says it: 7, 007, roll7, roll 007.
  defp roll?(sheet, q) do
    case q |> String.replace_prefix("roll", "") |> String.trim() |> Integer.parse() do
      {n, ""} -> n == sheet.roll_num
      _ -> false
    end
  end

  defp saints(q, words, _deep) do
    for {symbol, names} <- Saints.names(),
        title = Enum.join(names, " and "),
        hit = hit(q, words, title, [], nil) do
      entry(hit, title, title, "/Christ/saints/#{symbol}", nil)
    end
  end

  defp bible(q, words, _deep) do
    books =
      for {book, order} <- Enum.with_index(Bible.books()),
          hit = hit(q, words, book.name, [], nil) do
        entry(hit, order, book.name, "/Christ/bible/#{book.slug}", "#{book.chapters} chapters")
      end

    citation(q) ++ books
  end

  # "john 3:16" is not the name of anything, but it is an address.
  defp citation(q) do
    with true <- q =~ ~r/\d/,
         {:ok, %{book: slug, ranges: [{{chapter, verse}, _} | _]}} <- Citation.parse(q),
         %{name: name} <- Bible.book(slug),
         [_ | _] <- Bible.chapter(slug, chapter) do
      {title, anchor} =
        if verse,
          do: {"#{name} #{chapter}:#{verse}", "#v#{verse}"},
          else: {"#{name} #{chapter}", ""}

      [entry(0, -1, title, "/Christ/bible/#{slug}/#{chapter}#{anchor}", "Open the passage")]
    else
      _ -> []
    end
  end

  defp manual(q, words, _deep) do
    for {heading, order} <- Enum.with_index(manual_headings()),
        hit = hit(q, words, heading.text, [], nil) do
      entry(hit, order, heading.text, "/how-to##{heading.id}", nil)
    end
  end

  # Web.Docs keeps the rendered manual until the file changes.
  defp manual_headings do
    case Web.Docs.render_file(@manual) do
      {:ok, {_html, headings}} -> Enum.map(headings, &%{&1 | text: plain(&1.text)})
      _ -> []
    end
  end

  defp plain(text) do
    text
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&#39;", "'")
    |> String.replace("&quot;", "\"")
  end

  # ── Matching ──────────────────────────────────────────────────────

  # 0 the name is the query · 1 begins with it · 2 holds every word ·
  # 3 found in the other fields · {4, line} found in the text · nil not found.
  # The text is a function so it is only read when nothing nearer matched.
  defp hit(_q, [], _title, _fields, _text), do: nil

  defp hit(_q, words, title, fields, text) do
    q = Enum.join(words, " ")
    name = fold(title)
    rest = fields |> Enum.reject(&is_nil/1) |> Enum.map_join(" ", &fold/1)

    # "The Rosary" is "rosary" to someone typing it.
    bare = String.replace(name, ~r/^(the|a|an) /, "")

    cond do
      name == q or bare == q -> 0
      String.starts_with?(name, q) or String.starts_with?(bare, q) -> 1
      all?(words, name) -> 2
      all?(words, name <> " " <> rest) -> 3
      is_function(text) -> in_text(words, name <> " " <> rest, text.())
      true -> nil
    end
  end

  defp in_text(words, near, text) do
    if all?(words, near <> " " <> fold(text)) do
      {4, line_with(text, words)}
    end
  end

  # The line that holds the most of the query, for the reader to recognise.
  defp line_with(text, words) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, ["---", "![", "<"])))
    |> Enum.max_by(
      fn line ->
        folded = " " <> fold(line)
        Enum.count(words, &String.contains?(folded, " " <> &1))
      end,
      fn -> nil end
    )
    |> case do
      nil ->
        nil

      line ->
        line = String.replace(line, ~r/^[#>*\-\s]+|[*_`]/u, "")
        if String.length(line) > 160, do: String.slice(line, 0, 159) <> "…", else: line
    end
  end

  # A word matches where a word begins, so the haystack is led by a space.
  defp all?(words, haystack) do
    haystack = " " <> haystack
    Enum.all?(words, &String.contains?(haystack, " " <> &1))
  end

  # Lower case, with everything that is not a letter or a digit made a space:
  # "Pull-Ups" and "pull ups" are the same two words.
  defp fold(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end

  defp entry({rank, line}, order, title, path, context),
    do: entry(rank, order, title, path, line || context)

  defp entry(rank, order, title, path, context),
    do: %{rank: rank, order: order, title: title, path: path, context: presence(context)}

  defp presence(nil), do: nil

  defp presence(value),
    do: if(String.trim(to_string(value)) == "", do: nil, else: to_string(value))

  defp pad(n), do: n |> to_string() |> String.pad_leading(3, "0")

  defp safe(fun) do
    fun.()
  rescue
    _ -> []
  end
end
