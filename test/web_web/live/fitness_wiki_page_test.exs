defmodule WebWeb.FitnessWikiPageTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest

  # Runs against the invented vault in test/support/fixtures/fitness, whose one
  # exercise has a figure file beside the wiki.

  test "an exercise's page leads with its name, its one line and its figure", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/fitness/wiki/push-ups")

    assert has_element?(view, "h1.wiki-title", "Push-ups")
    assert has_element?(view, "p.wiki-lede", "A bodyweight press from the floor.")

    assert has_element?(
             view,
             "figure#figure-push-ups.fig[phx-hook][phx-update=ignore] svg[role=img]"
           )

    {figure, _} = :binary.match(html, ~s(id="figure-push-ups"))
    {body, _} = :binary.match(html, "A fixture exercise page.")
    assert figure < body
  end

  # The figure moves by SMIL in the markup; nothing is fetched to draw it.
  test "the figure is drawn and animated in the page itself", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/fitness/wiki/push-ups")
    [figure] = Regex.run(~r{<figure id="figure-push-ups".*?</figure>}s, html)

    assert figure =~ ~s(<animate attributeName="d")
    assert figure =~ ~s(repeatCount="indefinite")
    refute figure =~ "http"

    # A body, not a wire: the far limbs, the trunk, then the near limbs with
    # their edge, and the whole of it clipped at the floor it stands on.
    assert Regex.scan(~r/data-part="(\w+)"/, figure, capture: :all_but_first) ==
             [["leg_b"], ["arm_b"], ["trunk"], ["leg_a"], ["arm_a"]]

    assert figure =~ ~s(class="fig-edge")
    assert figure =~ ~s[clip-path="url(#figure-push-ups-ground)"]

    assert has_element?(view, "#figure-push-ups button[data-fig-toggle]", "Pause")
    assert has_element?(view, "#figure-push-ups button[data-fig-stop='0.0']", "top")
    assert has_element?(view, "#figure-push-ups button[data-fig-stop='1.5']", "bottom")
  end

  describe "once the figure has been filmed" do
    # Films go in the uploads folder; this one is the test's own.
    setup do
      uploads = Path.join(System.tmp_dir!(), "wiki-film-#{System.unique_integer([:positive])}")
      was = Application.get_env(:web, :uploads_path)
      Application.put_env(:web, :uploads_path, uploads)

      on_exit(fn ->
        Application.put_env(:web, :uploads_path, was)
        File.rm_rf(uploads)
      end)

      assert %{filmed: ["push-ups"]} = Web.Fitness.Clip.film()
      :ok
    end

    test "the page plays the film, and draws nothing itself", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/fitness/wiki/push-ups")
      [figure] = Regex.run(~r{<figure id="figure-push-ups".*?</figure>}s, html)

      assert has_element?(
               view,
               "figure#figure-push-ups.fig--film[phx-update=ignore] video.fig-film[muted][loop][playsinline]"
             )

      assert figure =~
               ~r|<source src="/uploads/figures/push-ups-[0-9a-f]{12}\.mp4" type="video/mp4"|

      assert figure =~ ~r|poster="/uploads/figures/push-ups-[0-9a-f]{12}\.jpg"|
      assert figure =~ ~s(width="720") and figure =~ ~s(height="720")

      # The hook starts it, so a reader who asked for stillness is given it.
      refute figure =~ "autoplay"
      refute figure =~ "<svg"
      refute figure =~ "<animate"
    end

    test "the poses' buttons carry where in the film each begins", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fitness/wiki/push-ups")

      assert has_element?(view, "#figure-push-ups button[data-fig-toggle]", "Pause")
      assert has_element?(view, "#figure-push-ups button[data-fig-stop='0.0']", "top")
      assert has_element?(view, "#figure-push-ups button[data-fig-stop='1.5']", "bottom")
    end

    test "the muscles lit in the film are named under it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fitness/wiki/push-ups")

      assert has_element?(view, "#figure-push-ups .fig-muscles .fig-muscle", "Chest")
    end

    test "the film is served, and seekable", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness/wiki/push-ups")
      [src] = Regex.run(~r|/uploads/figures/push-ups-[0-9a-f]{12}\.mp4|, html)

      whole = get(conn, src)
      assert whole.status == 200
      assert get_resp_header(whole, "content-type") == ["video/mp4"]
      assert get_resp_header(whole, "accept-ranges") == ["bytes"]

      part = conn |> put_req_header("range", "bytes=0-3") |> get(src)
      assert part.status == 206
      assert part.resp_body == "film"
    end
  end

  test "a tag opens the exercises that share it, and closing returns to the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/fitness/wiki/push-ups")

    view |> element("a.wiki-tag--category") |> render_click()
    assert_patch(view, "/fitness/wiki/push-ups?tag_type=category&tag=Push")
    assert has_element?(view, ".wiki-overlay a.wiki-overlay-link.is-current", "Push-ups")

    view |> element("button.wiki-overlay-close") |> render_click()
    assert_patch(view, "/fitness/wiki/push-ups")
    refute has_element?(view, ".wiki-overlay")
  end

  test "the page carries no colours of its own", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/fitness/wiki/push-ups")
    [main] = Regex.run(~r{<div class="container steel wiki-page">.*}s, html)

    refute main =~ ~r/style="[^"]*#[0-9a-fA-F]{3,6}/
    refute main =~ "rgba("
  end
end
