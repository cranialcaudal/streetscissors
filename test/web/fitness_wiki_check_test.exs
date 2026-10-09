defmodule Web.Fitness.WikiCheckTest do
  # Swaps the vault for a tmp one, so it cannot run beside tests that read it.
  use ExUnit.Case, async: false

  alias Web.Fitness.WikiCheck

  setup do
    tmp = Path.join(System.tmp_dir!(), "wiki_check_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join([tmp, "exercise-wiki", "upper"]))
    File.mkdir_p!(Path.join(tmp, "figures"))

    File.write!(Path.join(tmp, "references.md"), """
    ### smith-2001
    - authors: Smith A
    - year: 2001
    """)

    prev = Application.get_env(:web, :fitness_path)
    Application.put_env(:web, :fitness_path, tmp)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:web, :fitness_path, prev),
        else: Application.delete_env(:web, :fitness_path)

      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  defp page(tmp, slug, opts \\ []) do
    meta =
      Keyword.merge(
        [
          title: "Rows",
          muscle_group: "upper",
          anatomy: "Lats",
          functional_category: "Hypertrophy",
          short_description: "A row."
        ],
        Keyword.get(opts, :meta, [])
      )

    body =
      Keyword.get(opts, :body, """
      **Goal:** Pull.

      ### Execution
      Pull it.

      ### Why it works (theory)
      Pulling is pulling.

      ### Programming notes
      3 x 8.
      """)

    front =
      meta
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{v}" end)

    File.write!(
      Path.join([tmp, "exercise-wiki", "upper", slug <> ".md"]),
      "---\n#{front}\n---\n\n#{body}"
    )
  end

  defp said(slug),
    do: for(%{where: where, problem: problem} <- WikiCheck.problems(), where =~ slug, do: problem)

  test "pages that keep to the shape raise nothing", %{tmp: tmp} do
    page(tmp, "rows")
    page(tmp, "curls")

    assert WikiCheck.problems() == []
  end

  test "a missing key, and a page filed outside its muscle group", %{tmp: tmp} do
    page(tmp, "rows")
    page(tmp, "curls", meta: [anatomy: nil, muscle_group: "legs"])

    assert "has no anatomy" in said("curls")
    assert "says its muscle group is legs but is filed under upper" in said("curls")
  end

  test "a category only one page uses", %{tmp: tmp} do
    page(tmp, "rows")
    page(tmp, "curls")
    page(tmp, "presses", meta: [functional_category: "Arm Build"])

    assert [problem] = said("presses")
    assert problem =~ ~s(the only page in the category "Arm Build")
    assert said("rows") == []
  end

  test "a page without its Goal line or one of its sections", %{tmp: tmp} do
    page(tmp, "rows")
    page(tmp, "curls", body: "### Execution\nCurl.\n\n### Why it works (theory)\nIt does.\n")

    assert "has no Goal line" in said("curls")
    assert "has no ### Programming notes section" in said("curls")
  end

  test "the heading has to match whether the page cites anything", %{tmp: tmp} do
    page(tmp, "rows", meta: [references: "smith-2001"])

    page(tmp, "curls",
      body:
        "**Goal:** Curl.\n\n### Execution\nCurl.\n\n### Why it works\nIt does.\n\n### Programming notes\n3 x 8.\n"
    )

    assert [cited] = said("rows")
    assert cited =~ ~s(cites sources, so its section is "Why it works")
    assert [uncited] = said("curls")
    assert uncited =~ ~s[cites nothing, so its section is "Why it works (theory)"]
  end

  test "a day of the week in the body, and a citation the bibliography lacks", %{tmp: tmp} do
    page(tmp, "rows")

    page(tmp, "curls",
      meta: [references: "nobody-1999"],
      body:
        "**Goal:** Curl.\n\n### Execution\nCurl.\n\n### Why it works\nIt does.\n\n### Programming notes\n3 x 8 on Tuesday.\n"
    )

    assert Enum.any?(said("curls"), &(&1 =~ "names a day of the week (Tuesday)"))
    assert "cites nobody-1999, which is not in references.md" in said("curls")
  end

  test "a figure that belongs to no page, and one that does not hold together", %{tmp: tmp} do
    page(tmp, "rows")
    page(tmp, "curls")

    File.write!(Path.join([tmp, "figures", "ghost.json"]), ~s({"poses": [{"name": "stand"}]}))
    File.write!(Path.join([tmp, "figures", "rows.json"]), "{not json")

    assert Enum.any?(said("ghost"), &(&1 == "there is no exercise by that name in the wiki"))
    assert [broken] = said("rows.json")
    assert broken =~ "the figure is not drawn: not valid JSON"
  end
end
