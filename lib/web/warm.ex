defmodule Web.Warm do
  @moduledoc """
  Reads, once at boot, what the first visitor after a deploy would otherwise
  wait for.

  Several things are parsed on first use and then kept in `:persistent_term`:
  the lectionary (200 ms of JSON), the calendars, the saints, the books of the
  Bible the day's prayer is read from, and the manual. Each is instant ever
  after, but a deploy restarts the BEAM, and whoever asked for `/Christ` next
  paid for all of it: 260 ms against 5. This pays it before anyone asks.

  Runs in its own process after the Endpoint is up, so it never delays a
  boot, and nothing here can fail one: every step is on its own and a step
  that raises is skipped.
  """

  alias Web.Liturgy.{Calendar, Hours, Lectionary, Rosary, Saints}

  def run do
    today = Web.Clock.local_today()

    steps = [
      fn -> Calendar.day(today) end,
      fn -> Saints.names() end,
      fn -> Web.Bible.books() end,
      fn ->
        passages(
          for mass <- Lectionary.for_date(today).masses, r <- mass.readings, do: r.citation
        )
      end,
      fn ->
        passages(
          for hour <- Hours.hours(),
              %{citation: citation} <- Hours.office(hour, today).parts,
              do: citation
        )
      end,
      fn -> passages(for m <- Rosary.for_date(today).mysteries, do: m.citation) end,
      fn -> Web.Docs.render_file("docs/how-to.md") end,
      fn -> Web.Docs.render_file("docs/roadmap.md") end
    ]

    Enum.each(steps, &attempt/1)
  end

  defp passages(citations), do: Enum.each(citations, &attempt(fn -> Web.Bible.passage(&1) end))

  defp attempt(step) do
    step.()
  rescue
    _ -> :skipped
  catch
    _, _ -> :skipped
  end
end
