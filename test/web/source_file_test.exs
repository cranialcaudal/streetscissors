defmodule Web.SourceFileTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.SourceCheck
  alias Web.SourceFile

  setup do
    dir = Path.join(System.tmp_dir!(), "source_file_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  describe "write/4" do
    test "saves over the revision it was opened at, and refuses one that moved", %{dir: dir} do
      path = Path.join(dir, "week.md")
      File.write!(path, "one")
      {:ok, %{revision: opened}} = SourceFile.read(path)

      assert {:ok, two} = SourceFile.write(path, "two", opened)
      assert File.read!(path) == "two"
      assert two == SourceFile.revision("two")

      # Obsidian saved meanwhile: the stale revision is refused, and nothing lost.
      File.write!(path, "obsidian")

      assert {:error, :conflict, %{content: "obsidian"}} = SourceFile.write(path, "mine", two)
      assert File.read!(path) == "obsidian"
    end

    test "saving anyway keeps the replaced text in the trash first", %{dir: dir} do
      path = Path.join(dir, "week.md")
      trash = Path.join(dir, ".trash")
      File.write!(path, "obsidian")

      assert {:ok, _} = SourceFile.write(path, "mine", "stale", force: true, trash: trash)
      assert File.read!(path) == "mine"
      assert [kept] = File.ls!(trash)
      assert File.read!(Path.join(trash, kept)) == "obsidian"
    end

    test "a file not there yet is written over the empty revision", %{dir: dir} do
      path = Path.join(dir, "new.md")
      assert {:ok, %{content: "", revision: empty}} = SourceFile.read(path)
      assert {:ok, _} = SourceFile.write(path, "first", empty)
    end

    test "a file saved with \\r\\n keeps them when the browser sends \\n", %{dir: dir} do
      path = Path.join(dir, "post.md")
      original = "---\r\ntitle: Tide\r\n---\r\n![[roll012/3]] \r\nBody\r\n"
      File.write!(path, original)
      {:ok, %{revision: opened}} = SourceFile.read(path)

      # Saved unchanged from the admin: the same bytes, so the same revision.
      as_sent = String.replace(original, "\r\n", "\n")
      assert {:ok, ^opened} = SourceFile.write(path, as_sent, opened)
      assert File.read!(path) == original

      # An edit keeps the file's line endings on every line.
      assert {:ok, _} = SourceFile.write(path, as_sent <> "More\n", opened)
      assert File.read!(path) == original <> "More\r\n"
    end
  end

  describe "SourceCheck.check/2" do
    test "a week reads its days and blocks, and names a line it would skip" do
      good =
        "## Monday\n- 07:15-08:00 strength Lower day\n\n## Tuesday\n- 06:00-07:00 swim Pool\n"

      assert {:ok, "2 days, 2 blocks"} = SourceCheck.check("week", good)

      typo = "## Monday\n- 7.15-08:00 strength Lower day\n"
      assert {:error, reason} = SourceCheck.check("week", typo)
      assert reason =~ "7.15-08:00"

      assert {:error, "no days" <> _} = SourceCheck.check("week", "- 07:00-08:00 run Out\n")
    end

    test "a changelog heading with a bad date is named" do
      assert {:ok, "1 entries"} =
               SourceCheck.check("changelog", "## 2026-10-20 — New block\nText\n")

      assert {:error, _} = SourceCheck.check("changelog", "## 2026-13-40 — Typo\n")
    end

    test "a block says which field is wrong" do
      block = fn start ->
        "---\ntitle: Test\nstart: #{start}\nweeks: 2\nphases: 1 Push; 2 Deload\n---\n"
      end

      # 2026-10-19 is a Monday.
      assert {:ok, _} = SourceCheck.check("block:test", block.("2026-10-19"))

      assert {:error, "start: must be a Monday"} =
               SourceCheck.check("block:test", block.("2026-10-20"))

      assert {:error, "title: is missing"} =
               SourceCheck.check("block:test", "---\nweeks: 2\n---\n")
    end
  end
end
