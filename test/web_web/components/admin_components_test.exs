defmodule WebWeb.AdminComponentsTest do
  use WebWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias WebWeb.{AdminComponents, AdminNav}

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  describe "the rail's groups" do
    test "are the studio, the five programs and settings, in that order" do
      assert Enum.map(AdminNav.sections(), & &1.id) ==
               [:studio, :darkroom, :cuts, :writing, :training, :mail, :settings]

      headings = for %{heading: heading} <- AdminNav.sections(), heading, do: heading
      assert headings == ["Darkroom", "Cutting room", "Writing", "Training", "Mail"]
    end

    test "every page the rail names belongs to one group, and no page is named twice" do
      paths = for group <- AdminNav.sections(), link <- group.links, do: link.path
      assert paths == Enum.uniq(paths)
    end
  end

  describe "AdminNav.program/1" do
    test "answers with the program of the nearest rail link" do
      assert AdminNav.program("/admin/dashboard") == :studio
      assert AdminNav.program("/admin/scanner") == :darkroom
      assert AdminNav.program("/admin/darkroom") == :darkroom
      assert AdminNav.program("/admin/darkroom/taste") == :darkroom
      assert AdminNav.program("/admin/darkroom/065/6") == :darkroom
      assert AdminNav.program("/admin/cuts") == :cuts
      assert AdminNav.program("/admin/logs") == :cuts
      assert AdminNav.program("/admin/blog/new") == :writing
      assert AdminNav.program("/admin/keywords") == :writing
      assert AdminNav.program("/admin/health") == :writing
      assert AdminNav.program("/admin/fitness") == :training
      assert AdminNav.program("/admin/rides") == :training
      assert AdminNav.program("/admin/inbox") == :mail
      assert AdminNav.program("/admin/newsletter") == :mail
      assert AdminNav.program("/admin/settings") == :settings
    end

    test "is the neutral studio for a path the rail does not name" do
      assert AdminNav.program("/admin/nothing-here") == :studio
      assert AdminNav.program(nil) == :studio
      assert AdminNav.program_class("/admin/scanner") == "st-program--darkroom"
    end

    test "the layout puts the program on .adm-main", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/inbox")
      assert has_element?(view, "main#adm-main.adm-main.st-program--mail")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/darkroom/taste")
      assert has_element?(view, "main#adm-main.st-program--darkroom")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")
      assert has_element?(view, "main#adm-main.st-program--studio")
    end

    test "the rail's groups each carry their program's accent", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

      for program <- [:darkroom, :cuts, :writing, :training, :mail] do
        assert has_element?(view, "#adm-nav-#{program}.st-program--#{program} .adm-nav-mark")
      end

      # Settings sits at the foot, under no heading.
      assert has_element?(view, "#adm-nav-settings.adm-nav-group--foot a[href='/admin/settings']")
    end
  end

  # What the selector finds, as a list of LazyHTML nodes' tag-stripped text
  # and a way to read an attribute.
  defp find(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> find(selector) |> Enum.count()

  describe "program_card/1" do
    test "is one article wearing its program, whose only link is the title" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <AdminComponents.program_card program={:darkroom} title="Darkroom" href="/admin/darkroom">
          <:state>Roll 065 printed</:state>
          <:actions><a href="/admin/scanner" class="adm-btn">Scan</a></:actions>
        </AdminComponents.program_card>
        """)

      assert count(html, "article.st-card.st-program--darkroom") == 1

      # The title is the card's link (CSS stretches it over the card); the
      # action inside is a link of its own, not swallowed by the card.
      assert count(html, "h3 a.st-card-link[href='/admin/darkroom']") == 1
      assert count(html, ".st-card-actions a[href='/admin/scanner']") == 1
      assert count(html, "a") == 2
      refute html =~ ~r/<a[^>]*>[^<]*<a /
    end

    test "has a picture only when given one" do
      assigns = %{}

      without =
        rendered_to_string(~H"""
        <AdminComponents.program_card program={:cuts} title="Cutting room" href="/admin/cuts" />
        """)

      refute without =~ "st-card-picture"

      with_picture =
        rendered_to_string(~H"""
        <AdminComponents.program_card program={:cuts} title="Cutting room" href="/admin/cuts">
          <:picture><img src="/x.png" alt="" /></:picture>
        </AdminComponents.program_card>
        """)

      assert count(with_picture, ".st-card-picture img[src='/x.png']") == 1
    end

    test "a state line's tone is a class, and no tone is none" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <AdminComponents.program_card program={:mail} title="Mail" href="/admin/inbox" id="mail-card">
          <:state>Quiet</:state>
          <:state tone={:fail}>A failure</:state>
        </AdminComponents.program_card>
        """)

      assert count(html, "#mail-card li.st-card-line:not(.st-card-line--fail)") == 1
      assert count(html, "#mail-card li.st-card-line.st-card-line--fail") == 1
      # Nothing draws a state line unless it is given one, nor an actions row.
      refute html =~ "st-card-actions"
    end
  end

  describe "status_strip/1" do
    test "is one list of figures; a link only where an item has an href" do
      html =
        render_component(&AdminComponents.status_strip/1,
          label: "Site figures",
          items: [
            %{label: "Posts", value: 4, href: "/admin/blog"},
            %{label: "Views", value: 128},
            %{label: "Drive", value: "absent", tone: :fail, href: "#system"}
          ]
        )

      assert count(html, "ul.st-strip[aria-label='Site figures']") == 1
      assert count(html, "li.st-strip-item") == 3
      assert count(html, "a.st-strip-link[href='/admin/blog']") == 1
      assert count(html, "a.st-strip-link[href='#system']") == 1
      # "Views" has no href, so it is not a link.
      assert count(html, "span.st-strip-link") == 1
    end

    test "only a warning or a failure shows its tone" do
      html =
        render_component(&AdminComponents.status_strip/1,
          items: [
            %{label: "Mail", value: "clear", tone: :ok},
            %{label: "Snapshot", value: "3 days old", tone: :warn},
            %{label: "Drive", value: "absent", tone: :fail},
            %{label: "Posts", value: 4}
          ]
        )

      assert count(html, "li.st-strip-item--warn") == 1
      assert count(html, "li.st-strip-item--fail") == 1
      # Said for a screen reader as well as shown; an ok item is not announced.
      assert count(html, ".adm-sr") == 2
      assert html =~ "failing"
      assert html =~ "needs a look"
    end

    test "draws a sparkline for two or more values, flat for equal ones, none for fewer" do
      html =
        render_component(&AdminComponents.status_strip/1,
          items: [
            %{label: "Rising", value: 9, spark: [1, 2, 3]},
            %{label: "Flat", value: 3, spark: [3, 3, 3]},
            %{label: "One", value: 1, spark: [1]},
            %{label: "None", value: 0}
          ]
        )

      assert count(html, "svg.st-strip-spark") == 2

      [rising, flat] =
        html |> find("svg.st-strip-spark polyline") |> LazyHTML.attribute("points")

      heights = fn points ->
        for pair <- String.split(points, " "),
            do: pair |> String.split(",") |> List.last() |> String.to_float()
      end

      # Left to right the rising line climbs (a smaller y is higher); a flat
      # series is one height.
      assert heights.(rising) == Enum.sort(heights.(rising), :desc)
      assert heights.(rising) |> Enum.uniq() |> length() == 3
      assert heights.(flat) |> Enum.uniq() |> length() == 1
    end
  end
end
