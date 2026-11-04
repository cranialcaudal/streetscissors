defmodule Web.FrontmatterTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.Vault

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
end
