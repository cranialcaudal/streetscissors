defmodule WebWeb.FaithControllerTest do
  use WebWeb.ConnCase, async: true

  test "GET /Christ is the whole day: saints, fast and every prayer in place, and no more",
       %{conn: conn} do
    html = conn |> get(~p"/Christ?date=2026-10-06") |> html_response(200)

    assert html =~ "Tuesday of the Twenty-seventh Week in Ordinary Time"
    # The saints of the day are named, each a link to a page of his own,
    # which is where the life is.
    assert html =~ ~s(<a href="/Christ/saints/bruno">)
    refute html =~ "Carthusians"
    refute html =~ "CC BY-SA 4.0"

    assert html =~ "The fast of the Rule"
    assert html =~ "A fast day under the Rule of Saint Albert"

    # Each prayer is written out on the page, behind its own <details>.
    for id <- ~w(lauds midday readings vespers rosary compline) do
      assert html =~ ~s(<details class="faith-hour" id="#{id}")
    end

    assert html =~ "O God, come to my assistance."
    assert html =~ "The Angel of the Lord declared unto Mary."
    assert html =~ "Luke 10:38-42"
    assert html =~ "The Agony in the Garden"
    assert html =~ "Hail, holy Queen"

    # A prayer known by heart is its name, with the words behind a <details>
    # that is closed until asked for. The psalms stay written out.
    assert html =~ ~r{<details class="faith-known">\s*<summary>\s*<span>The Our Father}
    assert html =~ ~r{<details class="faith-known">\s*<summary>\s*<span>Glory Be}
    assert html =~ ~r{<details class="faith-known">\s*<summary>\s*<span>The Angelus}
    refute html =~ ~s(<details class="faith-known" open)
    refute html =~ "faith-doxology"
    assert html =~ ~s(class="faith-verses faith-verses--lines")
    assert html =~ ~s(href="/Christ/hours/vespers?date=2026-10-06")

    # The guide to the fast is no longer on the page.
    refute html =~ "faith-guide"
    refute html =~ "necessitas non habet legem"
  end

  test "the old address and the lower-case one lead to /Christ", %{conn: conn} do
    assert redirected_to(get(conn, "/faith"), 301) == "/Christ"

    assert redirected_to(get(conn, "/christ/hours/lauds?date=2026-10-06"), 301) ==
             "/Christ/hours/lauds?date=2026-10-06"
  end

  test "another day is marked as such, with the days either side and a way back", %{conn: conn} do
    html = conn |> get(~p"/Christ?date=2001-03-07") |> html_response(200)

    assert html =~ "not today"
    assert html =~ ~s(href="/Christ?date=2001-03-06" rel="prev")
    assert html =~ ~s(href="/Christ?date=2001-03-08" rel="next")
    assert html =~ ~s(<a href="/Christ">Today</a>)
    # A memorial in Lent is kept only as a commemoration.
    assert html =~ "Saints Perpetua and Felicity"
    assert html =~ "only as a commemoration"
  end

  test "a solemnity of the Order leads the day", %{conn: conn} do
    html = conn |> get(~p"/Christ?date=2026-10-15") |> html_response(200)

    assert html =~ ~s(href="/Christ/saints/teresa_avila")
    assert html =~ "which these pages count as free of the fast"
  end

  test "a saint has a page, and an unknown one does not", %{conn: conn} do
    html = conn |> get(~p"/Christ/saints/john_of_cross") |> html_response(200)

    assert html =~ "Saint John of the Cross, our Father"
    assert html =~ "December 14"
    assert html =~ "Kept this year on"
    assert html =~ "Wikipedia"

    assert conn |> get("/Christ/saints/nobody") |> html_response(404)
    # On the calendar, but with no life on file.
    assert conn |> get("/Christ/saints/carmelite_souls") |> html_response(404)
  end

  test "the calendar is a month of days, each a link", %{conn: conn} do
    html = conn |> get(~p"/Christ/calendar?month=2026-10") |> html_response(200)

    assert html =~ "October 2026"
    assert html =~ ~s(href="/Christ?date=2026-10-15")
    assert html =~ "Saint Teresa of Jesus, our Mother"
    assert html =~ "fast of the Rule"
    assert html =~ ~s(href="/Christ/calendar?month=2026-09" rel="prev")
    assert html =~ ~s(href="/Christ/calendar?month=2026-11" rel="next")

    assert conn |> get("/Christ/calendar?month=nonsense") |> html_response(200) =~
             "Calendar of the Discalced Carmelites"
  end

  test "the pages are unlisted and load nothing from another site", %{conn: conn} do
    for path <-
          ~w(/Christ /Christ/hours/lauds /Christ/readings /Christ/bible/luke/10 /Christ/rosary) do
      html = conn |> get(path) |> html_response(200)
      assert html =~ ~s(<meta name="robots" content="noindex, nofollow">)
      [main] = Regex.run(~r{<main.*?</main>}s, html)
      refute main =~ "universalis.com"
      refute main =~ ~s(src="http)
      refute main =~ "<script"
    end
  end

  test "an hour is prayed from the hosted Bible", %{conn: conn} do
    html = conn |> get(~p"/Christ/hours/lauds?date=2026-10-06") |> html_response(200)

    assert html =~ "Morning Prayer"
    assert html =~ "Tuesday, October 6"
    assert html =~ "O God, come to my assistance."
    # Psalm 85 is the Vulgate's 84.
    assert html =~ "Psalm 84"
    assert html =~ "Isaiah 26:1-4, 7-9, 12"
    assert html =~ "Benedictus"
    assert html =~ "Blessed is the Lord God of Israel"
    assert html =~ ~s(href="/Christ/hours/lauds?date=2026-10-07" rel="next")
    assert html =~ "not the official text"
  end

  test "Night Prayer ends with the Salve, and with the Regina Caeli in Easter", %{conn: conn} do
    assert conn |> get(~p"/Christ/hours/compline?date=2026-10-06") |> html_response(200) =~
             "Hail, holy Queen"

    assert conn |> get(~p"/Christ/hours/compline?date=2027-04-06") |> html_response(200) =~
             "Queen of Heaven, rejoice"
  end

  test "an unknown hour is a 404, and a bad date is today", %{conn: conn} do
    assert conn |> get("/Christ/hours/matins") |> html_response(404)

    assert conn |> get("/Christ/hours/lauds?date=yesterday") |> html_response(200) =~
             "Morning Prayer"
  end

  test "the readings of the day, in full", %{conn: conn} do
    html = conn |> get(~p"/Christ/readings?date=2026-10-06") |> html_response(200)

    assert html =~ "Galatians 1:13-24"
    assert html =~ "Luke 10:38-42"
    assert html =~ "Martha"
    assert html =~ ~s(href="/Christ/bible/luke/10#v38")
  end

  test "the readings say so on a day only Carmel keeps", %{conn: conn} do
    html = conn |> get(~p"/Christ/readings?date=2026-07-16") |> html_response(200)

    assert html =~
             "In the Carmelite calendar today is The Blessed Virgin Mary of Mount Carmel"
  end

  test "the Angelus", %{conn: conn} do
    html = conn |> get(~p"/Christ/angelus") |> html_response(200)

    assert html =~ "The Angel of the Lord declared unto Mary." or
             html =~ "Queen of Heaven, rejoice"
  end

  test "the Rosary: written out, and bead by bead", %{conn: conn} do
    html = conn |> get(~p"/Christ/rosary?set=joyful") |> html_response(200)

    assert html =~ "The Joyful Mysteries"
    assert html =~ "The Annunciation"
    assert html =~ "Luke 1:26-38"
    assert html =~ "Hail Mary, full of grace"

    # The written form is the order of prayer and the mysteries by name: each
    # mystery's scripture is behind its own closed <details>, twice over (the
    # written form and the bead-by-bead step), and so are the prayers' words.
    [written] = Regex.run(~r{<div data-rosary-text>.*}s, html)
    assert written =~ "one Our Father, ten Hail Marys, one Glory Be and the Fatima Prayer"
    assert length(Regex.scan(~r{<h3 class="faith-mystery">}, written)) == 6
    assert length(Regex.scan(~r{<span>Scripture<span class="faith-known-what">}, written)) == 5
    assert written =~ ~r{<span>Scripture<span class="faith-known-what">Luke 1:26-38</span>}
    assert written =~ ~r{<details class="faith-known">\s*<summary>\s*<span>The Hail Mary}
    refute written =~ "<details open"
    [before_scripture | _] = String.split(written, "faith-known", parts: 2)
    refute before_scripture =~ "faith-passage"

    # The steps app.js walks.
    assert html =~ ~s(data-bead="small" data-title="Hail Mary, 10 of 10")
    assert html =~ ~s(data-title="The Fifth Mystery: The Finding in the Temple")
    refute html =~ "Scripture does not narrate"

    html = conn |> get(~p"/Christ/rosary?set=glorious") |> html_response(200)
    assert html =~ "Scripture does not narrate the Assumption."

    assert conn |> get(~p"/Christ/rosary?set=nonsense") |> html_response(200) =~
             "The mysteries customarily prayed today."
  end

  test "the Bible: shelves, a book, a chapter", %{conn: conn} do
    html = conn |> get(~p"/Christ/bible") |> html_response(200)
    assert html =~ "Catholic Public Domain Version"
    assert html =~ ~s(href="/Christ/bible/sirach")

    assert conn |> get(~p"/Christ/bible/luke") |> html_response(200) =~
             ~s(href="/Christ/bible/luke/24")

    assert redirected_to(get(conn, ~p"/Christ/bible/jude")) == "/Christ/bible/jude/1"

    html = conn |> get(~p"/Christ/bible/psalms/22") |> html_response(200)
    assert html =~ "Psalm 22"
    assert html =~ "The Lord directs me"
    assert html =~ ~s(id="v1")
    assert html =~ ~s(href="/Christ/bible/psalms/21" rel="prev")
    assert html =~ ~s(href="/Christ/bible/psalms/23" rel="next")
  end

  test "the Bible's go-to box opens a passage as it is written", %{conn: conn} do
    go = fn q -> redirected_to(get(conn, ~p"/Christ/bible/go?#{[q: q]}")) end

    assert go.("Lk 10:38-42") == "/Christ/bible/luke/10#v38"
    assert go.("Psalm 22") == "/Christ/bible/psalms/22"
    assert go.("1 cor 13") == "/Christ/bible/1-corinthians/13"
    assert go.("Sirach") == "/Christ/bible/sirach"

    html = conn |> get(~p"/Christ/bible/go?#{[q: "Hezekiah 3:16"]}") |> html_response(200)
    assert html =~ "could not be read as a book, chapter and verse"
    assert html =~ ~s(value="Hezekiah 3:16")
  end

  test "what the Bible does not have is a 404", %{conn: conn} do
    for path <- ["/Christ/bible/hezekiah", "/Christ/bible/luke/25", "/Christ/bible/luke/ten"] do
      assert conn |> get(path) |> html_response(404)
    end
  end
end
