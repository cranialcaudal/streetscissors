defmodule Web.Liturgy.Fast do
  @moduledoc """
  What a day asks by way of fasting: the Church's law, and Carmel's Rule.

  **The Rule of Saint Albert** (chapter 16) keeps the fast every day except
  Sundays, from the feast of the Exaltation of the Holy Cross until the day of
  the Lord's Resurrection, unless sickness, weakness or another just cause
  counsels breaking it, "for necessity has no law". So the season runs from
  September 14 to Holy Saturday. Sundays are outside it by the Rule's own
  words. Solemnities are counted outside it here as well; that is this site's
  reading, by analogy with canon 1251, which lifts Friday abstinence on a
  solemnity, and the page says so. All Souls ranks with the solemnities but is
  a commemoration, and stays a fast day.

  **The Church's law** (canons 1249-1253, as applied in the United States):
  fasting and abstinence from meat on Ash Wednesday and Good Friday,
  abstinence on the Fridays of Lent, and on every other Friday abstinence
  commended, with another penance allowed in its place. A Friday that is a
  solemnity carries none (canon 1251).

  Nothing here depends on who is reading: it is the day's discipline as the
  texts give it, for anyone.
  """

  alias Web.Liturgy.Calendar

  @doc """
  The discipline of a `Web.Liturgy.Calendar.day/1`:

      %{carmelite: %{season: boolean, fast: boolean, text: String.t()},
        church: nil | %{title: String.t(), text: String.t()}}
  """
  def for_day(%{date: date} = day) do
    %{carmelite: carmelite(day), church: church(day, Date.day_of_week(date))}
  end

  defp carmelite(%{date: date} = day) do
    cond do
      not in_season?(date) ->
        %{
          season: false,
          fast: false,
          text:
            "Outside the season of the Rule's fast, which runs from the Exaltation of the Holy Cross (September 14) until Easter."
        }

      Date.day_of_week(date) == 7 ->
        %{season: true, fast: false, text: "Sunday. The Rule excepts every Sunday from the fast."}

      day.celebration.rank == :solemnity ->
        %{
          season: true,
          fast: false,
          text:
            "A solemnity, which these pages count as free of the fast, as the Church counts it free of Friday abstinence."
        }

      true ->
        %{
          season: true,
          fast: true,
          text:
            "A fast day under the Rule of Saint Albert. A fast allows one full meal; in the United States, two smaller meals that together do not equal it may also be taken."
        }
    end
  end

  @doc "Whether `date` lies between the Exaltation of the Cross and Easter."
  def in_season?(%Date{year: year} = date) do
    Date.compare(date, Date.new!(year, 9, 14)) != :lt or
      Date.compare(date, Calendar.easter(year)) == :lt
  end

  defp church(%{temporal: %{title: "Ash Wednesday"}}, _weekday) do
    %{
      title: "Fast and abstinence",
      text: "Ash Wednesday. The Church's law requires fasting and abstinence from meat."
    }
  end

  defp church(%{temporal: %{title: "Friday of the Passion of the Lord" <> _}}, _weekday) do
    %{
      title: "Fast and abstinence",
      text: "Good Friday. The Church's law requires fasting and abstinence from meat."
    }
  end

  defp church(%{celebration: %{rank: :solemnity}}, 5), do: nil

  defp church(%{season: :lent}, 5) do
    %{
      title: "Abstinence",
      text: "A Friday of Lent. The Church's law requires abstinence from meat."
    }
  end

  defp church(_day, 5) do
    %{
      title: "Friday penance",
      text:
        "Friday, a day of penance. In the United States abstinence from meat is commended, and another penance may take its place."
    }
  end

  defp church(_day, _weekday), do: nil
end
