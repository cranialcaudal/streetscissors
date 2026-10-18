defmodule Web.Darkroom.Prior do
  @moduledoc """
  Where the print editor suggests a print's colour should start, before any
  hand moves a slider: the film's own physics and its average in the archive,
  leaned toward the author's taste. His ask (2026-10-17): "an equation where
  some attunement is approached over the average color balance of a film
  given its expected reciprocity and exposure condition".

  All of it works in `{rg, bg}` (`Web.Darkroom.Film`). For a print `i` on a
  film `s` (a stock, or a process when the roll names none):

      ĉ_i  = (S_s⁻¹ m_s + R_i⁻¹ g_i) / (S_s⁻¹ + R_i⁻¹)       the print's cast
      t_s  = α_s m_s + o_s                                   where it should sit
      Δ_i  = t_s − ĉ_i + r_s(T_i)                            the correction

  * `g_i` is the print's own cast (`Stats`: its near-neutral parts) and
    `R_i` how little that says: `0.02² / neutral`, so a print with little
    grey in it is read mostly from its film.
  * `m_s` and `S_s` are the film's average cast and its spread over the
    archive's prints (`Archive.groups/1`), the spread floored at `0.02²`.
    With fewer than three prints of the film there is no average, and the
    print stands for itself.
  * `α_s` is how much of the film's own character to keep (1 keeps it, 0
    makes every print grey-neutral) and `o_s` a lean of the author's own; both
    are learned from his edits (`Web.Darkroom.Taste`). Untaught, `α = 1` and
    `o = 0`: each print is brought to its film's average, which is the
    "attunement" with no taste in it yet.
  * `r_s(T)` is the datasheet's colour correction for an exposure of `T`
    seconds (`Film.reciprocity/2`), nothing when it was not long.

  `Δ` becomes Temp and Tint by the measured response of LightCraft's
  sliders. A grey print is offered no colour.
  """

  alias Web.Darkroom.{Archive, Film, Stats}
  alias Web.Negatives.RollMeta

  @floor 0.02 * 0.02

  @doc """
  The suggestion for a print: `%{sliders, lines, ...}`, `sliders` being what
  to set (`wb.temp`, `wb.tint`) and `lines` what was reasoned, in words.
  `opts`: `:groups` (the archive's averages, measured when absent), `:taste`
  (`%{alpha, offset}`), `:temp` (Temp's value now).
  """
  def suggest(roll_dir, frame, source, color, opts \\ []) do
    with {:ok, stats} <- Stats.read(source) do
      {group, stock} = Archive.group_of(roll_dir, color)
      seconds = RollMeta.exposure(roll_dir, frame)
      groups = Keyword.get_lazy(opts, :groups, fn -> Archive.groups() end)
      taste = Keyword.get(opts, :taste, %{alpha: 1.0, offset: {0.0, 0.0}})
      {:ok, compute(stats, group, stock, seconds, groups[group], taste, opts)}
    end
  end

  @doc false
  def compute(stats, group, stock, seconds, film, taste, opts \\ []) do
    grey? = color_less?(stats, group, stock)
    recip = Film.reciprocity(stock, seconds)
    g = stats.cast

    {estimate, target, film_line} =
      case film do
        %{n: n, cast: m, var: {vr, vb}} when n >= 3 ->
          r = @floor / max(stats.neutral, 0.02)

          c =
            {blend(elem(m, 0), max(vr, @floor), elem(g, 0), r),
             blend(elem(m, 1), max(vb, @floor), elem(g, 1), r)}

          t = add(scale(m, taste.alpha), taste.offset)
          {c, t, "#{label(group, stock)} averages #{cast_words(m)} over #{n} prints"}

        _ ->
          {g, add(scale(g, taste.alpha), taste.offset),
           "#{label(group, stock)}: too few prints for an average yet"}
      end

    delta = add(sub(target, estimate), recip.cast)

    sliders =
      if grey?, do: %{}, else: Film.sliders(delta, Keyword.get(opts, :temp, 6500.0))

    %{
      stats: stats,
      group: group,
      stock: stock && stock["name"],
      seconds: seconds,
      reciprocity: recip,
      cast: g,
      estimate: estimate,
      target: target,
      correction: delta,
      sliders: sliders,
      lines:
        Enum.reject(
          [
            film_line,
            "This print reads #{cast_words(g)}, from #{round(stats.neutral * 100)}% of it near neutral",
            reciprocity_line(recip, seconds),
            if(grey?, do: "Black and white: no colour to suggest")
          ],
          &is_nil/1
        )
    }
  end

  defp color_less?(stats, group, stock) do
    group == "BW" || (stock && stock["process"] == "BW") || stats.chroma < 0.004
  end

  defp blend(prior, s, obs, r), do: (prior / s + obs / r) / (1 / s + 1 / r)

  defp add({a, b}, {c, d}), do: {a + c, b + d}
  defp sub({a, b}, {c, d}), do: {a - c, b - d}
  defp scale({a, b}, k), do: {a * k, b * k}

  defp label(group, nil), do: group
  defp label(_group, stock), do: stock["name"]

  @doc "A cast in words: which way it leans and how far, in hundredths of density."
  def cast_words({rg, bg}) do
    parts =
      [
        if(abs(rg) >= 0.01, do: "#{if rg > 0, do: "red", else: "cyan"} #{round(abs(rg) * 100)}"),
        if(abs(bg) >= 0.01,
          do: "#{if bg > 0, do: "blue", else: "yellow"} #{round(abs(bg) * 100)}"
        )
      ]
      |> Enum.reject(&is_nil/1)

    if parts == [], do: "neutral", else: Enum.join(parts, ", ")
  end

  defp reciprocity_line(_recip, nil), do: nil

  defp reciprocity_line(%{status: :none}, seconds),
    do: "#{seconds} s needs no correction on this film"

  defp reciprocity_line(%{status: :published, filter: f, stops: stops}, seconds),
    do:
      "#{seconds} s: the sheet asks #{f || "no filter"}, +#{Float.round(stops * 1.0, 2)} stop (exposure already set by the scan)"

  defp reciprocity_line(%{status: :beyond, filter: f}, seconds),
    do: "#{seconds} s is past the sheet's last row; its #{f || "figure"} is used as a guess"

  defp reciprocity_line(%{status: :unpublished}, seconds),
    do: "#{seconds} s: the maker publishes nothing this long; learned from your edits instead"

  defp reciprocity_line(%{status: :unknown}, seconds),
    do: "#{seconds} s: no datasheet read for this film"
end
