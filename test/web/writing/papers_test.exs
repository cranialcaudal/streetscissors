defmodule Web.Writing.PapersTest do
  use ExUnit.Case, async: false

  alias Web.Writing.Papers

  setup do
    tmp = Path.join(System.tmp_dir!(), "papers-#{System.unique_integer([:positive])}")
    dir = Path.join(tmp, "writing")
    original = Application.get_env(:web, :writing_path)
    Application.put_env(:web, :writing_path, dir)

    on_exit(fn ->
      File.rm_rf!(tmp)

      if original,
        do: Application.put_env(:web, :writing_path, original),
        else: Application.delete_env(:web, :writing_path)
    end)

    {:ok, dir: dir, tmp: tmp}
  end

  test "an empty or missing folder lists nothing" do
    assert Papers.list() == []
  end

  test "a new paper starts from its kind's skeleton, with project lines", %{dir: dir} do
    assert {:ok, "tide-study"} = Papers.create("Tide Study", "article", ~D[2030-03-02])
    text = File.read!(Path.join(dir, "tide-study.md"))

    assert text =~ ~s(title: "Tide Study")
    assert text =~ "zotero: "
    assert text =~ "csl: "
    assert text =~ "## Methods (~1000 words)"
    refute text =~ "draft:"

    assert [%{slug: "tide-study", title: "Tide Study"} = paper] = Papers.list()
    assert paper.outline.beats_total > 5
    assert {:error, :exists} = Papers.create("Tide Study", "article")
    assert {:error, :blank} = Papers.create("  ", "article")
  end

  test "saving refuses to write over a file that changed on disk", %{dir: dir, tmp: tmp} do
    {:ok, slug} = Papers.create("Fog", "essay")
    {:ok, %{revision: rev}} = Papers.read_source(slug)

    File.write!(Path.join(dir, "fog.md"), "Edited in Obsidian.\n")

    assert {:error, :conflict, %{content: "Edited in Obsidian.\n"}} =
             Papers.write_source(slug, "Mine.\n", rev)

    assert {:ok, _} = Papers.write_source(slug, "Mine.\n", rev, force: true)
    assert File.read!(Path.join(dir, "fog.md")) == "Mine.\n"
    assert [_kept] = File.ls!(Path.join(tmp, ".trash"))
  end

  test "an unsafe slug is not found" do
    assert Papers.read_source("../../etc/passwd") == {:error, :not_found}
  end

  test "a preview renders citations against the paper's reading list" do
    text = """
    ---
    title: Fog
    ---

    ## Reading List

    - [x] **Lund, Mara.** *Fog Signals* (2015). ^lund2015

    ## One

    The horn sounds [@lund2015].
    """

    post = Papers.preview("fog", text)
    assert post.body =~ "([Lund 2015](#ref-lund2015))"
    assert post.draft == false
  end
end
