defmodule Web.Darkroom.Taste do
  @moduledoc """
  The author's taste, learned from what he does: every edit he saves
  (`edits/NN.json`) and every choice he makes between two grades of one
  print (`/admin/darkroom/taste`, kept in `<archive>/.darkroom/choices.jsonl`,
  a choice counting half an edit). Nothing is learned from anyone else.

  **Colour** is where he likes a film's prints to sit. Each edit says it: the
  print's cast as developed (`Stats`) moved by his Temp and Tint
  (`Film.cast_of/3`). For a film `s` with `n_s` such targets averaging
  `t̄_s`, the target is

      T_s = (n_s t̄_s + k (α m_s + o)) / (n_s + k),   k = 3

  shrunk toward one rule for every film, `α m_s + o` (how much of a film's
  own average `m_s` he keeps, and a lean of his own), fitted across all his
  edits by least squares; with no edits, `α = 1, o = 0`, which is
  `Web.Darkroom.Prior`'s untaught attunement. A film he has edited three
  times is a little his, thirty times nearly all his.

  **Every other slider** he moves is one small model, as the research for
  this recommended for one person's tens to hundreds of edits:

      y = μ + W f + a_s + b_k

  `f` the print's numbers as developed (`Stats.features/1`, standardized),
  `a_s` a film's offset and `b_k` a condition's (`sound`, or the bath's
  diagnosis from `film-develop`: `veil`, `uneven`, `blocked`), all fitted at
  once by weighted ridge regression whose penalties are the shrinkage: `W`
  held at 1, the offsets at 3, so a film or condition seen once barely moves
  the answer. A slider is predicted only once it has been moved in three
  edits; the rest stay where they are.
  """

  alias Web.Darkroom
  alias Web.Darkroom.{Archive, Film, Stats}
  alias Web.Negatives

  @k 3.0
  @colour ~w(wb.temp wb.tint)
  @min_examples 3
  @lambda_w 1.0
  @lambda_offset 3.0

  defp choices_path, do: Path.join([Negatives.base_path(), ".darkroom", "choices.jsonl"])

  # ── What he did ──────────────────────────────────────────────────────

  @doc """
  Every example: `%{group, condition, stats, controls, weight}`, a saved
  edit weighing 1 and a choice 0.5.
  """
  def examples(prints \\ Archive.prints()) do
    by_frame = Map.new(prints, &{{&1.roll, &1.frame}, &1})

    edits =
      for print <- prints, Darkroom.edited?(print.dir, print.frame) do
        recipe = Darkroom.recipe(print.dir, print.frame)
        example(print, recipe.controls, 1.0)
      end

    picked =
      for choice <- choices(),
          print = by_frame[{choice["roll"], choice["frame"]}],
          print != nil,
          do: example(print, choice["chosen"] || %{}, 0.5)

    edits ++ picked
  end

  defp example(print, controls, weight) do
    %{
      group: print.group,
      condition: condition(print.dir),
      stats: print.stats,
      controls: controls,
      weight: weight
    }
  end

  @doc "The bath's diagnosis `film-develop` gave the roll, or `sound`."
  def condition(roll_dir) do
    with {:ok, body} <- File.read(Path.join(roll_dir, "frames.json")),
         {:ok, %{"diagnosis" => diagnosis}} <- Jason.decode(body) do
      cond do
        is_map(diagnosis) and diagnosis["veil"] -> "veil"
        is_map(diagnosis) and diagnosis["blocked"] -> "blocked"
        is_map(diagnosis) and diagnosis["uneven"] -> "uneven"
        is_list(diagnosis) and diagnosis != [] -> to_string(hd(diagnosis))
        true -> "sound"
      end
    else
      _ -> "sound"
    end
  end

  @doc "His choices so far, oldest first."
  def choices do
    case File.read(choices_path()) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, %{} = choice} -> [choice]
            _ -> []
          end
        end)

      _ ->
        []
    end
  end

  @doc "Keeps a choice: the grade he took and the one he left, for a print."
  def choose(roll, frame, chosen, other) do
    path = choices_path()
    File.mkdir_p!(Path.dirname(path))

    line =
      Jason.encode!(%{
        "roll" => roll,
        "frame" => frame,
        "chosen" => chosen,
        "other" => other,
        "at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })

    File.write!(path, line <> "\n", [:append])
  end

  # ── The model ────────────────────────────────────────────────────────

  @doc """
  The model fitted to everything he has done: `%{n, choices, colour, sliders}`.
  `colour` gives each film's target (`target/2`), `sliders` the ridge fit per
  slider (`predict/4`).
  """
  def fit(prints \\ Archive.prints(), groups \\ nil, defaults \\ %{}) do
    fit_examples(examples(prints), groups || Archive.groups(prints), defaults)
  end

  @doc """
  The model fitted to the examples given (`examples/1`'s shape), not to
  everything: what `Web.Darkroom.Eval` needs to leave one out.
  """
  def fit_examples(examples, groups, defaults \\ %{}) do
    %{
      n: Enum.count(examples, &(&1.weight == 1.0)),
      choices: Enum.count(examples, &(&1.weight < 1.0)),
      colour: fit_colour(examples, groups),
      sliders: fit_sliders(examples, defaults),
      groups: groups
    }
  end

  @doc """
  `fit/3`, kept until what it was fitted to changes: the prints and their
  readings, each print's saved edit (by its file's time), the Taste page's
  choices and the defaults. Opening a print no longer refits the archive
  when nothing was saved or chosen since the last time.
  """
  def fit_cached(prints \\ Archive.prints(), groups \\ nil, defaults \\ %{}) do
    groups = groups || Archive.groups(prints)

    fingerprint =
      :erlang.phash2({
        Enum.map(
          prints,
          &{&1.dir, &1.frame, &1.stats, stamp(Darkroom.edits_path(&1.dir, &1.frame))}
        ),
        stamp(choices_path()),
        groups,
        defaults
      })

    key = {__MODULE__, :fit}

    case :persistent_term.get(key, nil) do
      {^fingerprint, model} ->
        model

      _ ->
        model = fit(prints, groups, defaults)
        :persistent_term.put(key, {fingerprint, model})
        model
    end
  end

  defp stamp(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime, size: size}} -> {mtime, size}
      _ -> nil
    end
  end

  defp fit_colour(examples, groups) do
    # What each colour example wanted: its cast as developed, moved by its grade.
    targets =
      for ex <- examples,
          ex.stats.chroma >= 0.004,
          %{cast: m} <- [groups[ex.group]] do
        temp = number(ex.controls["wb.temp"], 6500.0)
        tint = number(ex.controls["wb.tint"], 0.0)
        {dr, db} = Film.cast_of(6500.0, temp, tint)
        {rg, bg} = ex.stats.cast
        %{group: ex.group, m: m, t: {rg + dr, bg + db}, w: ex.weight}
      end

    {alpha, offset} = global_rule(targets)

    by_group =
      targets
      |> Enum.group_by(& &1.group)
      |> Map.new(fn {group, list} ->
        n = Enum.sum(Enum.map(list, & &1.w))
        mean = {wmean(list, &elem(&1.t, 0)), wmean(list, &elem(&1.t, 1))}
        {group, %{n: n, mean: mean}}
      end)

    %{alpha: alpha, offset: offset, by_group: by_group}
  end

  # α and o for t ≈ α m + o, by least squares over both ratios at once.
  defp global_rule(targets) when length(targets) < 3, do: {1.0, {0.0, 0.0}}

  defp global_rule(targets) do
    rows =
      Enum.flat_map(targets, fn %{m: {mr, mb}, t: {tr, tb}, w: w} ->
        [{[mr, 1.0, 0.0], tr, w}, {[mb, 0.0, 1.0], tb, w}]
      end)

    case solve_ridge(rows, [0.5, 1.0e-6, 1.0e-6], [1.0, 0.0, 0.0]) do
      {:ok, [alpha, or_, ob]} -> {alpha |> max(0.0) |> min(1.5), {or_, ob}}
      :error -> {1.0, {0.0, 0.0}}
    end
  end

  @doc """
  Where his prints of `group` should sit, `{rg, bg}`, and how many edits say
  so: `{target, n}`. The prior asks for `%{alpha, offset}`; this gives an
  offset that lands `α m_s + o` on `T_s`.
  """
  def taste_for(%{colour: colour, groups: groups}, group) do
    m = (groups[group] || %{cast: {0.0, 0.0}}).cast
    rule = add(scale(m, colour.alpha), colour.offset)

    target =
      case colour.by_group[group] do
        %{n: n, mean: mean} -> scale(add(scale(mean, n), scale(rule, @k)), 1 / (n + @k))
        nil -> rule
      end

    %{alpha: colour.alpha, offset: sub(target, scale(m, colour.alpha))}
  end

  # A recipe keeps only the sliders off their default, so a slider missing
  # from one stood at its default (`defaults`, from LightCraft's schema; 0
  # when not given, which most sliders' default is).
  defp fit_sliders(examples, defaults) do
    ids =
      examples
      |> Enum.flat_map(&Map.keys(&1.controls))
      |> Enum.frequencies()
      |> Enum.filter(fn {id, count} -> count >= @min_examples and id not in @colour end)
      |> Enum.map(&elem(&1, 0))

    feats = Enum.map(examples, &Stats.features(&1.stats))
    {means, sds} = standardize(feats)
    groups = examples |> Enum.map(& &1.group) |> Enum.uniq() |> Enum.sort()
    conditions = examples |> Enum.map(& &1.condition) |> Enum.uniq() |> Enum.sort()
    design = %{means: means, sds: sds, groups: groups, conditions: conditions}

    fits =
      Map.new(ids, fn id ->
        default = number(defaults[id], 0.0)

        rows =
          for {ex, f} <- Enum.zip(examples, feats) do
            {row(design, f, ex.group, ex.condition), number(ex.controls[id], default), ex.weight}
          end

        {id, solve_ridge(rows, penalties(design), nil)}
      end)

    %{design: design, fits: for({id, {:ok, beta}} <- fits, into: %{}, do: {id, beta})}
  end

  @doc """
  The sliders his taste would set for a print, as `%{id => value}`: only
  sliders he has moved in enough edits.
  """
  def predict(%{sliders: %{design: design, fits: fits}}, stats, group, condition) do
    x = row(design, Stats.features(stats), group, condition)
    Map.new(fits, fn {id, beta} -> {id, dot(x, beta)} end)
  end

  defp row(design, f, group, condition) do
    z = for {{v, m}, s} <- Enum.zip(Enum.zip(f, design.means), design.sds), do: (v - m) / s

    [1.0] ++
      z ++
      Enum.map(design.groups, &if(&1 == group, do: 1.0, else: 0.0)) ++
      Enum.map(design.conditions, &if(&1 == condition, do: 1.0, else: 0.0))
  end

  defp penalties(design) do
    [1.0e-6] ++
      List.duplicate(@lambda_w, length(design.means)) ++
      List.duplicate(@lambda_offset, length(design.groups) + length(design.conditions))
  end

  defp standardize([]),
    do:
      {List.duplicate(0.0, length(Stats.feature_names())),
       List.duplicate(1.0, length(Stats.feature_names()))}

  defp standardize(rows) do
    cols = Enum.zip_with(rows, & &1)

    Enum.map(cols, fn col ->
      m = Enum.sum(col) / length(col)
      sd = :math.sqrt(Enum.sum(Enum.map(col, &((&1 - m) * (&1 - m)))) / max(length(col) - 1, 1))
      {m, if(sd < 1.0e-9, do: 1.0, else: sd)}
    end)
    |> Enum.unzip()
  end

  @doc false
  # Weighted ridge: minimise Σ w (y − x·β)² + Σ λ_j (β_j − p_j)², with p the
  # prior (zero when nil), by the normal equations.
  def solve_ridge([], _lambdas, _prior), do: :error

  def solve_ridge(rows, lambdas, prior) do
    k = length(lambdas)
    prior = prior || List.duplicate(0.0, k)

    a =
      for i <- 0..(k - 1) do
        for j <- 0..(k - 1) do
          Enum.sum(for {x, _y, w} <- rows, do: w * Enum.at(x, i) * Enum.at(x, j)) +
            if(i == j, do: Enum.at(lambdas, i), else: 0.0)
        end
      end

    b =
      for i <- 0..(k - 1) do
        Enum.sum(for {x, y, w} <- rows, do: w * Enum.at(x, i) * y) +
          Enum.at(lambdas, i) * Enum.at(prior, i)
      end

    gauss(a, b)
  end

  # Gaussian elimination with partial pivoting.
  defp gauss(a, b) do
    n = length(b)
    m = Enum.zip_with([a, b], fn [row, bi] -> row ++ [bi] end)

    reduced =
      Enum.reduce_while(0..(n - 1), m, fn col, m ->
        {pivot_row, p} =
          m
          |> Enum.with_index()
          |> Enum.drop(col)
          |> Enum.max_by(fn {row, _} -> abs(Enum.at(row, col)) end)

        if abs(Enum.at(pivot_row, col)) < 1.0e-12 do
          {:halt, :singular}
        else
          m = m |> List.replace_at(p, Enum.at(m, col)) |> List.replace_at(col, pivot_row)
          pivot = Enum.at(m, col)

          m =
            m
            |> Enum.with_index()
            |> Enum.map(fn {row, i} ->
              if i == col do
                row
              else
                f = Enum.at(row, col) / Enum.at(pivot, col)
                Enum.zip_with(row, pivot, &(&1 - f * &2))
              end
            end)

          {:cont, m}
        end
      end)

    case reduced do
      :singular -> :error
      m -> {:ok, for({row, i} <- Enum.with_index(m), do: List.last(row) / Enum.at(row, i))}
    end
  end

  defp dot(x, beta), do: Enum.sum(Enum.zip_with(x, beta, &(&1 * &2)))

  defp wmean(list, f) do
    w = Enum.sum(Enum.map(list, & &1.w))
    Enum.sum(Enum.map(list, &(f.(&1) * &1.w))) / w
  end

  defp number(v, _d) when is_number(v), do: v * 1.0
  defp number(_v, d), do: d

  defp add({a, b}, {c, d}), do: {a + c, b + d}
  defp sub({a, b}, {c, d}), do: {a - c, b - d}
  defp scale({a, b}, k), do: {a * k, b * k}
end
