defmodule Web.NearbyTest do
  use Web.DataCase

  import Web.AudioFixtures

  alias Web.Nearby
  alias Web.NegativesFixtures, as: Fixture

  setup do
    tmp = Path.join(System.tmp_dir!(), "nearby-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    original = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:web, :blog_path, original)
    end)

    post = fn slug, title, date ->
      File.write!(
        Path.join(tmp, slug <> ".md"),
        "---\ntitle: #{title}\ndate: #{date}\n---\n\nBody.\n"
      )
    end

    post.("the-ferry-at-bowling-green", "The Ferry at Bowling Green", "2030-03-01")
    post.("tides-out", "Tide's Out", "2030-03-02")
    post.("on-grain", "On Grain", "2030-03-03")

    File.write!(
      Path.join(tmp, "wip.md"),
      "---\ntitle: The Ferry, Unfinished\ndraft: true\n---\n\nNo.\n"
    )

    {:ok, post: post}
  end

  defp paths(suggestions), do: Enum.map(suggestions, & &1.path)

  describe "a missing post" do
    test "offers the post whose name is closest: a typo" do
      assert [%{kind: "Essay", title: "The Ferry at Bowling Green", path: path} | _] =
               Nearby.suggest("/blog/the-ferry-at-bowling-gren")

      assert path == "/blog/the-ferry-at-bowling-green"
    end

    test "offers a post that kept the core of its old name: a rename" do
      assert paths(Nearby.suggest("/blog/ferry")) == ["/blog/the-ferry-at-bowling-green"]
      assert "/blog/tides-out" in paths(Nearby.suggest("/blog/Tide's%20Out"))
    end

    test "offers the newest posts when nothing is close" do
      assert paths(Nearby.suggest("/blog/zzzzzzzz")) == [
               "/blog/on-grain",
               "/blog/tides-out",
               "/blog/the-ferry-at-bowling-green"
             ]
    end

    test "never offers a draft" do
      for path <- ["/blog/wip", "/blog/the-ferry-unfinished", "/blog/zzzzzzzz"] do
        refute "/blog/wip" in paths(Nearby.suggest(path))
      end
    end
  end

  describe "a missing recording" do
    test "offers the logs nearest the day in the address" do
      log_fixture(recorded_on: ~D[2030-01-05])
      log_fixture(recorded_on: ~D[2030-03-02])
      log_fixture(recorded_on: ~D[2030-03-20])
      log_fixture(recorded_on: ~D[2030-06-01])

      assert [%{kind: "Log", path: "/logs/2030-03-02"}, %{path: "/logs/2030-03-20"}, _] =
               Nearby.suggest("/logs/2030-03-04")

      # Entry two of a day that has only one still lands on that day.
      assert [%{path: "/logs/2030-03-02"} | _] = Nearby.suggest("/logs/2030-03-02-2")
    end

    test "does not offer a recording that is not public" do
      log_fixture(recorded_on: ~D[2030-03-02], published: false)
      assert Nearby.suggest("/logs/2030-03-02") == []
    end
  end

  describe "a missing roll" do
    setup do
      root = Fixture.archive!()

      for roll <- ~w(011 012 013 020) do
        Fixture.put_roll!(root, roll: roll)
        Fixture.put_sheet!(root, "roll#{roll}_2026-01-01_120_bw", 2400, 3000)
      end

      :ok
    end

    test "offers the rolls nearest that number, by either address" do
      assert paths(Nearby.suggest("/negatives/roll/014")) == [
               "/negatives/roll/013",
               "/negatives/roll/012",
               "/negatives/roll/011"
             ]

      assert [%{kind: "Roll", path: "/negatives/roll/020"} | _] =
               Nearby.suggest("/archive/roll/roll099")
    end

    test "a frame that was never printed leads back to its roll" do
      assert [%{path: "/negatives/roll/012"} | _] =
               Nearby.suggest("/negatives/roll/012/frame/40")
    end
  end

  test "an empty day offers the nearest days that have work on them" do
    assert [%{kind: "Day", title: "Saturday, 2 March 2030", path: "/day/2030-03-02"} | _] =
             Nearby.suggest("/day/2030-03-02")

    assert [%{path: "/day/2030-03-03"}, %{path: "/day/2030-03-02"}, %{path: "/day/2030-03-01"}] =
             Nearby.suggest("/day/2030-05-09")
  end

  test "a year with nothing in it offers the years there are" do
    assert [%{kind: "Year", path: "/almanac/2030"} | _] = Nearby.suggest("/almanac/1999")
  end

  test "a misspelled exercise offers the one that was meant" do
    assert [%{kind: "Exercise", path: "/fitness/wiki/push-ups"}] =
             Nearby.suggest("/fitness/wiki/pushups")
  end

  describe "an address outside the site's sections" do
    test "a bare word close to a post's name finds the post" do
      assert paths(Nearby.suggest("/tides-out")) == ["/blog/tides-out"]
      assert Nearby.suggest("/something-else-entirely") == []
    end

    # Most 404s are scanners. Nothing is read from disk for them.
    test "a scanner's probe is offered nothing, and reads nothing", %{post: post} do
      Application.put_env(:web, :blog_path, "/nonexistent/blog/that/would/raise/if/listed")

      for probe <- ~w(/wp-login.php /.env /.git/config /xmlrpc.php /a/b/c/d /cgi-bin/luci/;stok=) do
        assert Nearby.suggest(probe) == [], "#{probe} was offered something"
      end

      assert is_function(post)
    end

    test "nonsense is an empty answer, never an error" do
      assert Nearby.suggest("") == []
      assert Nearby.suggest("/") == []
      assert Nearby.suggest(nil) == []
      assert Nearby.suggest("/day/not-a-date") |> is_list()
      assert Nearby.suggest("/blog/%E0%A4%A") |> is_list()
      assert Nearby.suggest("/negatives/roll/" <> String.duplicate("9", 400)) |> is_list()
    end
  end
end
