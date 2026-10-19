defmodule Web.Fitness.ChangelogTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.Changelog

  test "entries are dated headings with their paragraphs, newest first" do
    text = """
    # Changes

    ## 2026-10-19 — Box jumps open the lower day

    Three sets of three.

    ## 2026-10-26 - Get Sharp begins

    Eight weeks.

    ## not a date — skipped
    """

    assert [
             %{date: ~D[2026-10-26], title: "Get Sharp begins", body: "Eight weeks." <> _},
             %{
               date: ~D[2026-10-19],
               title: "Box jumps open the lower day",
               body: "Three sets of three."
             }
           ] = Changelog.parse(text)
  end

  test "a vault without the file has no entries" do
    assert Changelog.entries() == []
  end
end
