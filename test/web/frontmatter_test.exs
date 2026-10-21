defmodule Web.FrontmatterTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.{Vault, Week}

  test "splits a file written with \\n or \\r\\n the same way" do
    assert Web.Frontmatter.split("---\ntitle: A\n---\nbody\n") == {"title: A", "body\n"}
    assert Web.Frontmatter.split("---\r\ntitle: A\r\n---\r\nbody\r\n") == {"title: A", "body\r\n"}
  end

  test "a file with no frontmatter is all body" do
    assert Web.Frontmatter.split("# Heading\n") == {"", "# Heading\n"}
    assert Web.Frontmatter.strip("no fence") == "no fence"
  end

  test "the vault keeps a CRLF file's frontmatter" do
    meta = Vault.parse_frontmatter_text("---\r\ntitle: Squat\r\ngroup: legs\r\n---\r\nBody\r\n")
    assert meta["title"] == "Squat"
    assert meta["group"] == "legs"
  end

  test "the week reads a CRLF file's days" do
    week =
      Week.parse("---\r\ntitle: Week\r\n---\r\n## Monday\r\n- 07:15-08:00 strength Lower day\r\n")

    assert [%{blocks: [_]}] = week.days
  end
end
