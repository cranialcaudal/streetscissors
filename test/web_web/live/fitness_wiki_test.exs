defmodule WebWeb.FitnessWikiTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest

  # Runs against the invented vault in test/support/fixtures/fitness, which
  # holds one exercise: Push-ups (upper, Chest, Push).
  test "the wiki lists its exercises under a search field", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/fitness/wiki")

    assert has_element?(view, ~s(form#wiki-search[role="search"] input[name="q"]))
    assert html =~ ~s(href="/fitness/wiki/push-ups")
  end

  test "typing narrows the wiki and puts the query in the address", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/fitness/wiki")

    html = view |> element("#wiki-search") |> render_change(%{"q" => "Chest"})
    assert_patched(view, "/fitness/wiki?q=Chest")
    assert html =~ ~s(href="/fitness/wiki/push-ups")

    html = view |> element("#wiki-search") |> render_change(%{"q" => "deadlift"})
    assert_patched(view, "/fitness/wiki?q=deadlift")
    refute html =~ ~s(href="/fitness/wiki/push-ups")
    assert html =~ "No exercise matches “deadlift”."
    assert html =~ ~s(href="/search?q=deadlift")

    view |> element("#wiki-search") |> render_change(%{"q" => "  "})
    assert_patched(view, "/fitness/wiki")
  end

  test "a filtered wiki can be linked to, by name, group, anatomy or category", %{conn: conn} do
    for query <- ["push", "upper", "chest", "upper push"] do
      {:ok, _view, html} = live(conn, ~p"/fitness/wiki?#{[q: query]}")
      assert html =~ ~s(href="/fitness/wiki/push-ups"), "expected #{inspect(query)} to match"
      assert html =~ ~s(value="#{query}")
    end

    {:ok, _view, html} = live(conn, ~p"/fitness/wiki?q=push+legs")
    refute html =~ ~s(href="/fitness/wiki/push-ups")
  end
end
