defmodule WebWeb.FaithController do
  @moduledoc """
  The prayer pages: the liturgical day and its saints, the Hours, the
  readings at Mass, the Rosary, a calendar, and the Bible they are all read
  from.

  Everything a page shows is worked out from the date (`Web.Liturgy`) and
  read from the hosted Bible (`Web.Bible`), so nothing is fetched from another
  site at request time or by the reader's browser. The pages are the same for
  every reader: there is no account, no setting and nothing remembered.

  `/Christ` is the whole day on one page. Each prayer opens in place (a
  `<details>`, so it works without JavaScript) and also has a page of its own.
  "Today" is the Pacific-local date (`Web.Clock`), like the rest of the site,
  and `?date=YYYY-MM-DD` shows any other day; the calendar links there.

  Unlisted, like `/food`: out of the sitemap, disallowed in robots.txt, and
  `noindex, nofollow`.
  """
  use WebWeb, :controller

  alias Web.{Bible, Clock}
  alias Web.Bible.Citation
  alias Web.Liturgy.{Calendar, Fast, Hours, Lectionary, Prayers, Rosary, Saints, Sanctoral}
  alias WebWeb.SEO

  @description "The day's prayer in the manner of Carmel: the saints of the day, the Hours, the readings at Mass, the Rosary and the fast of the Rule of Saint Albert, read from a Bible hosted here."

  plug :unlisted

  def index(conn, params) do
    today = Clock.local_today()
    date = date(params)
    day = Calendar.day(date)

    conn
    |> page("Christ", ~p"/Christ", [{"Christ", ~p"/Christ"}])
    |> assign(:return_to, ~p"/")
    |> assign(:return_label, "return to homepage")
    |> render(:index,
      day: day,
      date: date,
      today: today,
      saints: saints(day),
      fast: Fast.for_day(day),
      offices: Map.new(Hours.hours(), &{&1, office(&1, date)}),
      readings: readings_for(date),
      rosary: rosary_set(Rosary.for_date(date)),
      midday: Prayers.midday(day.season)
    )
  end

  def hour(conn, %{"hour" => hour} = params) when hour in ~w(lauds vespers compline) do
    date = date(params)
    office = office(String.to_existing_atom(hour), date)
    path = ~p"/Christ/hours/#{hour}"

    conn
    |> page(office.name, path, [{"Christ", ~p"/Christ"}, {office.name, path}])
    |> render(:hour, office: office, date: date, today: Clock.local_today())
  end

  def hour(conn, _params), do: WebWeb.NotFound.render(conn)

  def angelus(conn, _params) do
    day = Calendar.day(Clock.local_today())
    midday = Prayers.midday(day.season)

    conn
    |> page(midday.title, ~p"/Christ/angelus", [
      {"Christ", ~p"/Christ"},
      {midday.title, ~p"/Christ/angelus"}
    ])
    |> render(:angelus, midday: midday, day: day)
  end

  def readings(conn, params) do
    date = date(params)

    conn
    |> page("Readings at Mass", ~p"/Christ/readings", [
      {"Christ", ~p"/Christ"},
      {"Readings", ~p"/Christ/readings"}
    ])
    |> render(:readings, readings: readings_for(date), date: date, today: Clock.local_today())
  end

  def rosary(conn, params) do
    today = Rosary.for_date(Clock.local_today())

    set =
      case Enum.find(Rosary.keys(), &(Atom.to_string(&1) == params["set"])) do
        nil -> today
        key -> Rosary.set(key)
      end

    set = rosary_set(set)

    conn
    |> page("The Rosary", ~p"/Christ/rosary", [
      {"Christ", ~p"/Christ"},
      {"The Rosary", ~p"/Christ/rosary"}
    ])
    |> render(:rosary,
      set: set,
      steps: Rosary.steps(set),
      today: today,
      sets: Enum.map(Rosary.keys(), &Rosary.set/1)
    )
  end

  def saint(conn, %{"symbol" => symbol}) do
    with {month, day, entry} <- Sanctoral.find(symbol),
         %{} = saint <- Saints.get(symbol) do
      today = Clock.local_today()
      path = ~p"/Christ/saints/#{symbol}"

      conn
      |> page(entry.title, path, [{"Christ", ~p"/Christ"}, {entry.title, path}])
      |> render(:saint,
        entry: entry,
        saint: saint,
        month: month,
        day: day,
        kept: kept(symbol, today),
        today: today
      )
    else
      _ -> WebWeb.NotFound.render(conn)
    end
  end

  def calendar(conn, params) do
    today = Clock.local_today()

    first =
      with month when is_binary(month) <- params["month"],
           {:ok, %Date{year: year} = date} when year in 1970..2199 <-
             Date.from_iso8601(month <> "-01") do
        date
      else
        _ -> Date.beginning_of_month(today)
      end

    days =
      for date <- Date.range(first, Date.end_of_month(first)) do
        day = Calendar.day(date)
        %{day: day, fast: Fast.for_day(day)}
      end

    conn
    |> page("Calendar", ~p"/Christ/calendar", [
      {"Christ", ~p"/Christ"},
      {"Calendar", ~p"/Christ/calendar"}
    ])
    |> render(:calendar,
      first: first,
      days: days,
      today: today,
      previous: first |> Date.add(-1) |> Date.beginning_of_month(),
      next: first |> Date.end_of_month() |> Date.add(1)
    )
  end

  def bible(conn, _params) do
    conn
    |> page("The Bible", ~p"/Christ/bible", [
      {"Christ", ~p"/Christ"},
      {"The Bible", ~p"/Christ/bible"}
    ])
    |> render(:bible, translation: Bible.translation(), books: Bible.books(), missed: nil)
  end

  @doc """
  The Bible's "go to" box: a citation typed as it would be written ("Lk
  10:38", "Psalm 22", "1 Cor 13") opens that chapter at that verse. The
  citation is read in the hosted Bible's own numbering, since that is what its
  pages are headed with.
  """
  def go(conn, params) do
    query = String.trim(params["q"] || "")

    with {:ok, %{book: slug, ranges: [{{chapter, verse}, _} | _]}} <- Citation.parse(query),
         [_ | _] <- Bible.chapter(slug, chapter) do
      anchor = if verse, do: "#v#{verse}", else: ""
      redirect(conn, to: ~p"/Christ/bible/#{slug}/#{chapter}" <> anchor)
    else
      _ ->
        case Citation.book_slug(query) do
          {:ok, slug} ->
            redirect(conn, to: ~p"/Christ/bible/#{slug}")

          {:error, _} ->
            conn
            |> page("The Bible", ~p"/Christ/bible", [
              {"Christ", ~p"/Christ"},
              {"The Bible", ~p"/Christ/bible"}
            ])
            |> render(:bible,
              translation: Bible.translation(),
              books: Bible.books(),
              missed: query
            )
        end
    end
  end

  def book(conn, %{"book" => slug}) do
    case Bible.book(slug) do
      nil -> WebWeb.NotFound.render(conn)
      %{chapters: 1} -> redirect(conn, to: ~p"/Christ/bible/#{slug}/1")
      book -> chapter_list(conn, book)
    end
  end

  def chapter(conn, %{"book" => slug, "chapter" => chapter}) do
    with %{} = book <- Bible.book(slug),
         {number, ""} <- Integer.parse(chapter),
         [_ | _] = verses <- Bible.chapter(slug, number) do
      {previous, next} = Bible.neighbours(slug, number)
      title = chapter_title(book, number)

      conn
      |> page(title, ~p"/Christ/bible/#{slug}/#{number}", [
        {"Christ", ~p"/Christ"},
        {"The Bible", ~p"/Christ/bible"},
        {book.name, ~p"/Christ/bible/#{slug}"}
      ])
      |> assign(:return_to, ~p"/Christ/bible")
      |> assign(:return_label, "return to the Bible")
      |> render(:chapter,
        book: book,
        number: number,
        title: title,
        verses: verses,
        previous: previous,
        next: next,
        translation: Bible.translation()
      )
    else
      _ -> WebWeb.NotFound.render(conn)
    end
  end

  defp chapter_list(conn, book) do
    conn
    |> page(book.name, ~p"/Christ/bible/#{book.slug}", [
      {"Christ", ~p"/Christ"},
      {"The Bible", ~p"/Christ/bible"},
      {book.name, ~p"/Christ/bible/#{book.slug}"}
    ])
    |> assign(:return_to, ~p"/Christ/bible")
    |> assign(:return_label, "return to the Bible")
    |> render(:book, book: book)
  end

  @doc "\"Psalm 22\" for the Psalms, \"Luke 10\" for everything else."
  def chapter_title(%{slug: "psalms"}, number), do: "Psalm #{number}"
  def chapter_title(%{chapters: 1, name: name}, _number), do: name
  def chapter_title(%{name: name}, number), do: "#{name} #{number}"

  # ── What the pages are made of ────────────────────────────────────────────

  # The celebration when it is a saint's or a feast's, then the day's
  # optional memorials, each with the life on file for it (or nil).
  defp saints(day) do
    kept = if day.celebration.source == :sanctoral, do: [day.celebration], else: []
    for entry <- kept ++ day.optional, do: %{entry: entry, saint: Saints.get(entry.symbol)}
  end

  # The date `symbol` is kept on in the year of `today`, allowing for a
  # transfer, or nil in a year it gives way altogether.
  defp kept(symbol, today) do
    with {month, day, _} <- Sanctoral.find(symbol) do
      fixed = Date.new!(today.year, month, day)

      Enum.find(Date.range(fixed, Date.add(fixed, 21)), fn date ->
        day = Calendar.day(date)
        day.celebration.symbol == symbol or Enum.any?(day.optional, &(&1.symbol == symbol))
      end)
    end
  end

  defp office(hour, date) do
    office = Hours.office(hour, date)

    parts =
      Enum.map(office.parts, fn
        %{citation: citation} = part -> Map.put(part, :passage, passage(citation))
        part -> part
      end)

    summary =
      for %{type: type, citation: citation} <- office.parts, type in [:psalm, :canticle] do
        hosted(citation)
      end

    office |> Map.put(:parts, parts) |> Map.put(:summary, Enum.join(summary, " · "))
  end

  defp readings_for(date) do
    found = Lectionary.for_date(date)

    masses =
      for mass <- found.masses do
        readings =
          for reading <- mass.readings do
            Map.put(reading, :passage, passage(reading.citation, psalm_opts(reading)))
          end

        %{mass | readings: readings}
      end

    summary =
      case found.masses do
        [mass | _] ->
          for(r <- mass.readings, r.kind not in ["alleluia", "verse_before_gospel"], do: r)
          |> Enum.map_join(" · ", &hosted(&1.citation, psalm_opts(&1)))

        [] ->
          "not in the lectionary held here"
      end

    %{
      masses: masses,
      from: found.from,
      summary: summary,
      day: Calendar.day(date),
      usa_day: Calendar.day(date, calendar: :usa)
    }
  end

  defp psalm_opts(%{psalm: true}), do: [default: "psalms"]
  defp psalm_opts(_reading), do: []

  defp rosary_set(set) do
    %{set | mysteries: for(m <- set.mysteries, do: Map.put(m, :passage, passage(m.citation)))}
  end

  # A passage that cannot be found is shown as its citation alone, so a
  # misprint in the lectionary costs one reading and not the page.
  defp passage(citation, opts \\ []) do
    case Bible.passage(citation, opts) do
      {:ok, passage} -> passage
      {:error, _} -> nil
    end
  end

  # A citation as the hosted Bible numbers it, which is what the passage
  # under it will be headed.
  defp hosted(citation, opts \\ []) do
    case Bible.passage(citation, opts) do
      {:ok, passage} -> passage.citation
      {:error, _} -> citation
    end
  end

  defp date(%{"date" => iso}) do
    case Date.from_iso8601(iso) do
      {:ok, %Date{year: year} = date} when year in 1970..2199 -> date
      _ -> Clock.local_today()
    end
  end

  defp date(_params), do: Clock.local_today()

  defp page(conn, title, path, crumbs) do
    conn
    |> assign(:page_title, title)
    |> assign(:og_title, "#{title} · streetscissors")
    |> assign(:og_description, @description)
    |> assign(:meta_description, @description)
    |> assign(:canonical_path, path)
    |> assign(:json_ld, [SEO.breadcrumb_json_ld([{"Home", ~p"/"} | crumbs])])
    |> assign(:return_to, ~p"/Christ")
    |> assign(:return_label, "return to Christ")
  end

  defp unlisted(conn, _opts), do: assign(conn, :robots, "noindex, nofollow")
end
