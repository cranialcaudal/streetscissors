defmodule Web.SearchTest do
  use Web.DataCase

  import Web.AudioFixtures
  import Web.RidesFixtures

  alias Web.Search

  setup do
    tmp = Path.join(System.tmp_dir!(), "search-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    original = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:web, :blog_path, original)
    end)

    post = fn slug, front, body ->
      File.write!(Path.join(tmp, slug <> ".md"), "---\n#{front}\n---\n\n#{body}\n")
    end

    post.(
      "the-ferry-at-bowling-green",
      "title: The Ferry at Bowling Green\ndate: 2030-03-01\nkeywords: nyc, harbor",
      "First line.\n\nThe gulls followed the boat to Staten Island."
    )

    post.("on-grain", "title: On Grain\ndate: 2030-03-03", "Tri-X pushed two stops.")
    post.("wip", "title: The Ferry, Unfinished\ndraft: true", "gulls gulls gulls")

    :ok
  end

  defp section(groups, name), do: Enum.find(groups, &(&1.section == name))
  defp paths(nil), do: []
  defp paths(group), do: Enum.map(group.results, & &1.path)

  test "a post is found by its title, its keywords and its text, never a draft" do
    assert paths(section(Search.search("ferry"), "Blog")) == ["/blog/the-ferry-at-bowling-green"]
    assert paths(section(Search.search("harbor"), "Blog")) == ["/blog/the-ferry-at-bowling-green"]

    assert [%{path: "/blog/the-ferry-at-bowling-green", context: context}] =
             section(Search.search("gulls"), "Blog").results

    # Found in the text, so the line it was found on is what is shown.
    assert context == "The gulls followed the boat to Staten Island."
  end

  test "every word has to appear, at the start of a word" do
    assert paths(section(Search.search("ferry green"), "Blog")) ==
             ["/blog/the-ferry-at-bowling-green"]

    assert Search.search("ferry grain") == []
    # "rain" is inside "Grain" but begins no word.
    assert section(Search.search("rain"), "Blog") == nil
    assert paths(section(Search.search("GRAIN"), "Blog")) == ["/blog/on-grain"]
  end

  test "a name that is the query leads the ones that only contain it" do
    File.write!(
      Path.join(Application.get_env(:web, :blog_path), "grain.md"),
      "---\ntitle: Grain\ndate: 2029-01-01\n---\n\nBody.\n"
    )

    assert paths(section(Search.search("grain"), "Blog")) == ["/blog/grain", "/blog/on-grain"]
  end

  test "a query too short to mean anything finds nothing" do
    assert Search.search("") == []
    assert Search.search(" f ") == []
    assert Search.search(nil) == []
    assert Search.search("---") == []
    refute Search.searchable?("f")
    assert Search.searchable?("fe")
    assert String.length(Search.clean(String.duplicate("a", 500))) == 80
  end

  test "captain's logs, by caption and keyword, published ones only" do
    log = log_fixture(recorded_on: ~D[2026-09-18], caption: "Leaving the slip")
    log_fixture(recorded_on: ~D[2026-09-19], caption: "Leaving, unpublished", published: false)

    assert paths(section(Search.search("leaving"), "Captain's logs")) == ["/logs/#{log.slug}"]
    assert paths(section(Search.search("nyc"), "Captain's logs")) == ["/logs/#{log.slug}"]
  end

  test "exercises, by name, muscle group, anatomy and text" do
    for query <- ["push-ups", "push ups", "chest", "upper", "fixture exercise"] do
      assert "/fitness/wiki/push-ups" in paths(section(Search.search(query), "Exercise wiki")),
             "expected #{inspect(query)} to find the push-up"
    end
  end

  test "activities, by name" do
    ride = ride_fixture(%{name: "Putah Creek out and back"})

    assert paths(section(Search.search("putah"), "Activities")) == ["/fitness/rides/#{ride.id}"]
  end

  # Komoot calls most tours "Ride" or "Run" and a bicycle "touringbicycle".
  test "activities, by the words people use for them" do
    ride =
      ride_fixture(%{name: "Ride", sport: "touringbicycle", started_at: ~U[2026-07-08 18:00:00Z]})

    run = ride_fixture(%{name: "Run", sport: "jogging", started_at: ~U[2026-08-02 15:00:00Z]})

    found = fn query -> paths(section(Search.search(query), "Activities")) end
    ride_path = "/fitness/rides/#{ride.id}"
    run_path = "/fitness/rides/#{run.id}"

    for query <- ["bike", "cycling", "bicycle", "bike touring", "july 2026", "komoot july"] do
      assert found.(query) == [ride_path], "expected #{inspect(query)} to find the ride only"
    end

    for query <- ["running", "jog", "august", "2026-08-02"] do
      assert found.(query) == [run_path], "expected #{inspect(query)} to find the run only"
    end

    # "komoot" is all of them, newest first.
    assert found.("komoot") == [run_path, ride_path]

    # Two rides called "Ride" are told apart by what is under the name.
    assert [%{title: "Ride", context: "Bike touring · 24.9 mi · 8 July 2026"}] =
             section(Search.search("bike"), "Activities").results

    assert section(Search.search("komoot"), "Activities").all == "/fitness/rides"
  end

  test "saints, books of the Bible, a citation, and the manual" do
    assert "/Christ/saints/john_of_cross" in paths(section(Search.search("john cross"), "Saints"))

    assert paths(section(Search.search("galatians"), "The Bible")) == ["/Christ/bible/galatians"]

    assert [%{title: "John 3:16", path: "/Christ/bible/john/3#v16"} | _] =
             section(Search.search("john 3:16"), "The Bible").results

    assert Enum.any?(
             paths(section(Search.search("keywords"), "How it works")),
             &String.starts_with?(&1, "/how-to#")
           )
  end

  test "pages are found by name and by the other words for them" do
    for {query, path} <- [
          {"guestbook", "/guestbook"},
          {"rss", "/feed"},
          {"vespers", "/Christ/hours/vespers"},
          {"sorrowful", "/Christ/rosary?set=sorrowful"},
          {"annunciation", "/Christ/rosary?set=joyful"},
          {"sunday", "/fitness/day/sunday"},
          {"manual", "/how-to"},
          {"terminal", "/pc"}
        ] do
      assert path in paths(section(Search.search(query), "Pages")),
             "expected #{inspect(query)} to find #{path}"
    end
  end

  # "All of my pages, always": a public address with no parameters has to be
  # in Search.pages/0, or be one of the few named here with the reason. A new
  # page added to the router fails this until it is made findable.
  test "every public page in the router is in the search" do
    not_pages = %{
      "/admin/login" => "the admin's door",
      "/admin/logout" => "the admin's door",
      "/sitemap.xml" => "for crawlers",
      "/Christ/bible/go" => "the citation box's target, a redirect",
      "/search/suggest" => "what the search field asks as it is typed in (JSON)",
      "/archive" => "the old address of /negatives",
      "/fitness/export/csv" => "a download"
    }

    redirects = [
      WebWeb.LegacyRedirectController,
      WebWeb.RideRedirectController,
      WebWeb.AdminSessionController
    ]

    searchable = MapSet.new(Search.pages(), & &1.path)

    missing =
      for %{verb: :get, path: path, plug: plug} <- WebWeb.Router.__routes__(),
          not String.contains?(path, [":", "*"]),
          not String.starts_with?(path, [
            "/admin/",
            "/dev",
            "/api",
            "/health",
            "/share",
            "/uploads"
          ]) or
            is_map_key(not_pages, path),
          plug not in redirects,
          path not in searchable,
          not is_map_key(not_pages, path),
          path not in Search.unlisted(),
          do: path

    assert missing == [],
           "these pages are not in Web.Search.pages/0 (add them to @fixed): #{inspect(missing)}"

    # And nothing in the list points nowhere.
    for %{path: path} <- Search.pages() do
      route = path |> String.split("?") |> hd()

      assert %{} = Phoenix.Router.route_info(WebWeb.Router, "GET", route, "localhost"),
             "#{path} is in the search but not in the router"
    end
  end

  test "the unlisted pages stay out" do
    for query <- ["food", "kitchen", "england", "meals"] do
      refute Enum.any?(paths(section(Search.search(query), "Pages")), &(&1 in Search.unlisted()))
    end
  end

  describe "suggest/1" do
    test "offers the nearest names across sections, the exact one first" do
      log_fixture(recorded_on: ~D[2026-09-18], caption: "The ferry, leaving")

      assert [%{title: "The Ferry at Bowling Green", path: path, section: "Blog"} | rest] =
               Search.suggest("the ferry")

      assert path == "/blog/the-ferry-at-bowling-green"
      assert Enum.any?(rest, &(&1.section == "Captain's logs"))
      assert length(Search.suggest("the")) <= 8
    end

    test "works on half a word, which is the point" do
      assert "/fitness/wiki/push-ups" in Enum.map(Search.suggest("pus"), & &1.path)
      assert "/guestbook" in Enum.map(Search.suggest("gue"), & &1.path)
      assert "/Christ/hours/vespers" in Enum.map(Search.suggest("vesp"), & &1.path)
    end

    test "goes by name, never by text, and offers nothing for nothing" do
      # "gulls" is only in a post's body: the search finds it, the field does not offer it.
      assert Search.suggest("gulls") == []
      assert section(Search.search("gulls"), "Blog")
      assert Search.suggest("") == []
      assert Search.suggest("f") == []
      assert Search.suggest(nil) == []
    end
  end

  test "a section shows twelve and counts the rest" do
    blog = Application.get_env(:web, :blog_path)

    for n <- 1..15 do
      File.write!(
        Path.join(blog, "tide-#{n}.md"),
        "---\ntitle: Tide table #{n}\ndate: 2029-01-#{String.pad_leading("#{n}", 2, "0")}\n---\n\nBody.\n"
      )
    end

    assert %{results: results, more: 3} = section(Search.search("tide"), "Blog")
    assert length(results) == 12
  end
end
