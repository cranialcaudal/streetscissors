defmodule Web.StudioTest do
  # The archive, the blog and the fitness vault are process-wide settings.
  use Web.DataCase, async: false

  import Web.AudioFixtures
  import Web.GeneralFixtures
  import Web.NegativesFixtures

  alias Web.Contact
  alias Web.Cuts
  alias Web.Rides
  alias Web.Scanner.Pipeline
  alias Web.Studio

  defp counts(overrides \\ %{}),
    do: Map.merge(%{inbox: 0, guestbook: 0, citations: 0, logs: 0}, Map.new(overrides))

  defp tmp_dir(name) do
    dir = Path.join(System.tmp_dir!(), "studio-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  describe "the Darkroom" do
    test "an empty archive has nothing on the bench, nothing waiting and no pictures" do
      archive!()

      assert %{bench: nil, waiting: [], edited: 0, recent: [], newest_print: nil, choices: 0} =
               Studio.darkroom()
    end

    test "the roll on the bench is the unlisted one, with its strips, prints and singles owed" do
      root = archive!()
      put_roll!(root, roll: "065", format: "35mm", color: "color")

      dir = Pipeline.roll_dir("066", "2026-10-18", "35mm", "color")
      File.mkdir_p!(dir)

      put_strips!(dir, [
        {656, 2152, [{1, {0, 0, 656, 700}}, {2, {0, 726, 656, 700}}]},
        {656, 2152, [{3, {0, 0, 656, 700}}]},
        {656, 2152, [{4, {0, 0, 656, 700}}]}
      ])

      put_print!(dir, 1)

      File.write!(
        Path.join(dir, "selects.json"),
        Jason.encode!(%{"frames" => %{"1" => %{"chosen" => true}, "3" => %{"chosen" => true}}})
      )

      assert %{bench: bench, waiting: []} = Studio.darkroom()

      assert %{roll: "066", format: "35mm", color: "color", strips: 3, prints: 1, owed: 1} =
               bench
    end

    test "rolls scanned but not published wait, apart from the one on the bench" do
      archive!()
      File.mkdir_p!(Pipeline.roll_dir("066", "2026-10-18", "35mm", "color"))
      older = Pipeline.roll_dir("064", "2026-10-10", "120", "bw")
      File.mkdir_p!(older)
      # The bench is the newest touched, so touch the other one first.
      File.touch!(older, System.os_time(:second) - 3600)

      assert %{bench: %{roll: "066"}, waiting: [%{roll: "064", format: "120", color: "bw"}]} =
               Studio.darkroom()
    end

    test "the prints edited last, newest edit first, with a thumbnail each" do
      root = archive!()
      colour = put_roll!(root, roll: "065", format: "35mm", color: "color")
      bw = put_roll!(root, roll: "057", format: "35mm", color: "bw")
      for n <- [6, 7], do: put_print!(colour, n)
      put_print!(bw, 11)

      edit = fn folder, frame, age ->
        path = Path.join([folder, "edits", String.pad_leading("#{frame}", 2, "0") <> ".json"])
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, "{}")
        File.touch!(path, System.os_time(:second) - age)
      end

      edit.(colour, 6, 7200)
      edit.(bw, 11, 60)
      # An edit whose print is gone is counted nowhere near the picture.
      edit.(colour, 9, 10)

      assert %{edited: 3, recent: recent, newest_print: nil} = Studio.darkroom()
      assert [%{roll: "057", frame: 11}, %{roll: "065", frame: 6}] = recent
      assert Enum.all?(recent, &(&1.url =~ "/negatives/frame/" and &1.url =~ "w=480"))
      assert [%DateTime{}, %DateTime{}] = Enum.map(recent, & &1.at)
    end

    test "with no edit the picture is the newest roll's last print" do
      root = archive!()
      old = put_roll!(root, roll: "057", format: "35mm", color: "bw")
      new = put_roll!(root, roll: "065", format: "35mm", color: "color")
      put_sheet!(root, "roll057_2026-01-01_35mm_bw", 100, 100)
      put_sheet!(root, "roll065_2026-01-01_35mm_color", 100, 100)
      put_print!(old, 11)
      for n <- [6, 7], do: put_print!(new, n)

      assert %{edited: 0, recent: [], newest_print: %{roll: "065", frame: 7, url: url}} =
               Studio.darkroom()

      assert url =~ "/negatives/frame/65/7"
    end

    test "Taste choices are counted from the file that keeps them" do
      root = archive!()
      assert Studio.darkroom().choices == 0

      File.mkdir_p!(Path.join(root, ".darkroom"))

      File.write!(
        Path.join([root, ".darkroom", "choices.jsonl"]),
        ~s({"roll":"065","frame":6}\n{"roll":"065","frame":7}\nnot json\n)
      )

      assert Studio.darkroom().choices == 2
    end
  end

  describe "the Cutting room and the logs" do
    test "nothing yet" do
      assert %{total: 0, cuts: [], newest_log: nil, logs: logs} = Studio.cuts(%{})
      assert logs == %{unpublished: 0, transcoding: 0, failed: 0}
    end

    test "a cut is its name, length, clips and whether it has been rendered" do
      {:ok, cut} = Cuts.create_cut("Sunday log")
      on_exit(fn -> File.rm_rf(Cuts.bin(cut.id)) end)

      timeline = %{
        "clips" => [
          %{"id" => "c-1", "kind" => "still", "frame" => "065/6", "duration" => 4000},
          %{"id" => "c-2", "kind" => "still", "frame" => "065/7", "duration" => 3500}
        ],
        "titles" => [],
        "sounds" => []
      }

      cut |> Ecto.Changeset.change(timeline: timeline) |> Repo.update!()

      assert %{total: 1, cuts: [one]} = Studio.cuts(%{})
      assert %{name: "Sunday log", length_ms: 7500, clips: 2, rendered?: false} = one
      assert one.status == "draft"

      log = log_fixture(%{published: false})
      cut |> Ecto.Changeset.change(status: "done", audio_log_id: log.id) |> Repo.update!()

      assert %{cuts: [%{rendered?: true, log: log_title}]} = Studio.cuts(%{})
      assert log_title == Web.Audio.Log.title(log)
    end

    test "logs ready and unpublished, transcoding and failed, and the newest with its poster" do
      log_fixture(%{published: false, recorded_on: ~D[2026-10-01]})
      log_fixture(%{published: true, recorded_on: ~D[2026-10-02]})
      log_fixture(%{status: "pending", published: false, recorded_on: ~D[2026-10-03]})
      log_fixture(%{status: "failed", published: false, recorded_on: ~D[2026-10-04]})

      newest =
        log_fixture(%{
          published: true,
          recorded_on: ~D[2026-10-05],
          caption: "Morning at the bench",
          poster_path: "/uploads/logs/x/poster.jpg"
        })

      assert %{logs: %{unpublished: 1, transcoding: 1, failed: 1}, newest_log: log} =
               Studio.cuts(Web.Audio.count_by_status())

      assert %{
               recorded_on: ~D[2026-10-05],
               caption: "Morning at the bench",
               poster: "/uploads/logs/x/poster.jpg",
               status: "ready",
               published: true
             } = log

      assert newest.recorded_on == log.recorded_on
    end
  end

  describe "Writing" do
    setup do
      blog = tmp_dir("blog")
      original = Application.get_env(:web, :blog_path)
      Application.put_env(:web, :blog_path, blog)
      on_exit(fn -> Application.put_env(:web, :blog_path, original) end)
      %{blog: blog}
    end

    defp post!(blog, slug, front, body \\ "A paragraph that is long enough to stand in for text.") do
      File.write!(Path.join(blog, slug <> ".md"), "---\n#{front}\n---\n\n#{body}\n")
    end

    test "an empty blog has nothing to say" do
      assert %{drafts: 0, published: 0, last: nil, newest_draft: nil} = Studio.writing()
    end

    test "drafts, the last post published, and the posts missing a description or keywords", %{
      blog: blog
    } do
      post!(
        blog,
        "kept",
        ~s(title: "Kept"\ndescription: "A line."\ndate: "2026-10-03"\nkeywords: a, b)
      )

      post!(blog, "bare", ~s(title: "Bare"\ndate: "2026-09-01"))
      post!(blog, "no-words", ~s(title: "No words"\ndescription: "Has one."\ndate: "2026-08-01"))
      post!(blog, "wip", ~s(title: "Work in progress"\ndate: "2026-10-10"\ndraft: true))

      assert %{
               drafts: 1,
               newest_draft: %{slug: "wip", title: "Work in progress"},
               published: 3,
               last: %{slug: "kept", title: "Kept", date: ~D[2026-10-03]},
               no_description: 1,
               no_keywords: 2
             } = Studio.writing()
    end
  end

  describe "Training" do
    setup do
      fitness = tmp_dir("fitness")
      File.mkdir_p!(Path.join(fitness, "weekly"))

      File.write!(
        Path.join([fitness, "weekly", "thursday.md"]),
        "---\ntitle: Thursday — Lower Body\ntab: Thursday\ntheme: legs\n---\n\n- [ ] Squats\n"
      )

      File.write!(
        Path.join([fitness, "weekly", "friday.md"]),
        "---\ntitle: Friday — Swim or Run\ntab: Friday\n---\n\n- [ ] Swim\n"
      )

      original = Application.get_env(:web, :fitness_path)
      Application.put_env(:web, :fitness_path, fitness)
      on_exit(fn -> Application.put_env(:web, :fitness_path, original) end)
      :ok
    end

    # 2026-10-15 is a Thursday; at noon UTC it is the same day in Pacific time.
    @thursday ~U[2026-10-15 19:00:00Z]
    @friday ~U[2026-10-16 19:00:00Z]
    @saturday ~U[2026-10-17 19:00:00Z]

    test "today's word is the day's theme, or its title without the weekday" do
      assert %{today: %{slug: "thursday", word: "legs"}} = Studio.training([], @thursday)

      assert %{today: %{slug: "friday", word: nil, title: "Swim or Run"}} =
               Studio.training([], @friday)

      assert %{today: nil, newest: nil, activities: 0} = Studio.training([], @saturday)
    end

    test "the newest activity, how many are on file and Komoot's last pass" do
      Web.RidesFixtures.ride_fixture(%{name: "Early loop", started_at: ~U[2026-07-01 15:00:00Z]})

      Web.RidesFixtures.ride_fixture(%{
        name: "Evening loop",
        started_at: ~U[2026-07-08 18:00:00Z]
      })

      assert %{newest: newest, activities: 2, sync: sync} =
               Studio.training(Rides.list_rides(), @thursday)

      assert %{name: "Evening loop", sport: "racebike", distance_m: 40_000.0} = newest
      assert is_nil(newest.picture)
      assert %{at: nil, status: nil} = sync

      Web.Rides.KomootSync.record_run({:ok, %{unchanged: true}})
      assert %{at: %DateTime{}, status: :ok} = Studio.training([], @thursday).sync
    end
  end

  describe "Mail" do
    test "nothing waiting" do
      assert %{open: 0, flagged: 0, held: 0, citations: 0, newest: nil} = Studio.mail(counts())
    end

    test "the rail's counts, and the newest open message's sender and first line" do
      {:ok, _} =
        Contact.create_message(%{name: "Ada", email: "ada@example.com", message: "First one"})

      {:ok, newest} =
        Contact.create_message(%{
          name: "Bo Reader",
          email: "bo@example.com",
          message: "\n\nYour feed is missing last week's log.\nAnd a second line."
        })

      {:ok, _} = Contact.update_status(newest.id, "attention")
      guestbook_entry_fixture(%{approved: false})

      mail = Studio.mail(WebWeb.AdminNav.counts())

      assert %{open: 2, flagged: 1, held: 1, citations: 0, newest: message} = mail

      assert %{name: "Bo Reader", line: "Your feed is missing last week's log.", letter?: false} =
               message

      assert %DateTime{} = message.at
    end

    test "an archived message is not the newest" do
      {:ok, old} =
        Contact.create_message(%{name: "Old", email: "old@example.com", message: "Done with"})

      {:ok, _} = Contact.update_status(old.id, "archived")
      assert %{newest: nil} = Studio.mail(counts())
    end

    test "a first line is cut at a word" do
      line = String.duplicate("word ", 40)
      cut = Studio.first_line(line, 30)
      assert String.ends_with?(cut, "…")
      assert String.length(cut) <= 31
      assert Studio.first_line("  \n short  \nsecond") == "short"
    end
  end

  describe "the whole floor" do
    test "is every program's state and what is on file" do
      archive!()
      floor = Studio.floor(counts: counts())

      assert Map.keys(floor) |> Enum.sort() ==
               [:cuts, :darkroom, :logs, :mail, :on_file, :training, :writing]

      assert %{posts: _, logs: 0, log_drafts: 0, subscribers: 0, activities: 0, signatures: 0} =
               floor.on_file
    end
  end
end
