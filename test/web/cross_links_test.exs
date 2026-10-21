defmodule Web.CrossLinksTest do
  # The blog's folder is application config: not async.
  use WebWeb.ConnCase, async: false

  import Web.AudioFixtures

  alias Web.Pieces

  describe "Pieces.refs/1" do
    test "reads a related: line into canonical refs, leaving out what is not one" do
      assert Pieces.refs("frame:12/3, log:2026-09-18, post:tides, nonsense, frame:x") ==
               ["frame:012/3", "log:2026-09-18", "post:tides"]

      assert Pieces.refs(["frame:roll7/1", "frame:007/1"]) == ["frame:007/1"]
      assert Pieces.refs(nil) == []
    end
  end

  describe "a log's post_ref" do
    test "must name a post, and blank is none" do
      log = log_fixture()
      assert {:ok, %{post_ref: nil}} = Web.Logs.update_log(log, %{"post_ref" => ""})
      assert {:error, changeset} = Web.Logs.update_log(log, %{"post_ref" => "frame:001/1"})
      assert %{post_ref: [_]} = Web.DataCase.errors_on(changeset)
    end
  end

  describe "a post's page" do
    setup do
      dir = Path.join(System.tmp_dir!(), "blog_related_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      previous = Application.get_env(:web, :blog_path)
      Application.put_env(:web, :blog_path, dir)

      on_exit(fn ->
        Application.put_env(:web, :blog_path, previous)
        File.rm_rf(dir)
      end)

      %{dir: dir}
    end

    test "shows what it goes with, and the logs that name it, both ways", %{conn: conn, dir: dir} do
      named = log_fixture(recorded_on: ~D[2026-09-18], caption: "Named in the post")

      log_fixture(
        recorded_on: ~D[2026-09-19],
        caption: "Says it goes with",
        post_ref: "post:harbour"
      )

      File.write!(Path.join(dir, "harbour.md"), """
      ---
      title: Harbour
      date: 2026-09-20
      related: log:#{named.slug}, log:no-such-log
      ---

      The words.
      """)

      html = conn |> get(~p"/blog/harbour") |> html_response(200)
      assert html =~ ~s(id="related")
      assert html =~ "/logs/#{named.slug}"
      assert html =~ "/logs/2026-09-19"
      # A ref to nothing is left out of the page (content health lists it).
      refute html =~ "no-such-log"

      log_html = conn |> get(~p"/logs/2026-09-19") |> html_response(200)
      assert log_html =~ ~s(id="log-post")
      assert log_html =~ "/blog/harbour"
    end
  end
end
