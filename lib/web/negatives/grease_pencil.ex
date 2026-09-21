defmodule Web.Negatives.GreasePencil do
  @moduledoc """
  The ring a china marker leaves around a frame worth printing.

  Marking selects on a paper contact sheet is done with a grease pencil — a
  waxy stick that skips on the gloss, rides wide of the frame, and never draws
  the same circle twice. That last part is the point: a sheet of identical
  vector ellipses reads as software, and this page is trying to read as a
  sheet someone went over by hand.

  So every ring is generated from its own seed. The seed is
  `:erlang.phash2({roll, frame})`, which means the shape is *varied but fixed*:
  frame 7 of roll 13 gets the same ring on every render, in every process, after
  every restart, while no two frames anywhere in the archive share one. The
  wordmark in `WebWeb.CoreComponents` takes the same line — hand-set, never
  random — and for the same reason: randomness that changes between the static
  render and the connected mount makes the page twitch on load.

  ## How the shape is made

  An ellipse sampled at intervals, with its radius modulated by three sine
  harmonics at random phase, is what gives an organic wobble rather than a
  jagged one — noise per point would look like a shaky hand, and this is a
  steady hand with a blunt tool. The samples are smoothed into cubic segments
  through a Catmull-Rom spline, the sweep runs past a full turn so the ends
  cross the way a real circle closes, and roughly a third of rings go round
  twice.

  Each ring is drawn as two passes: a full-weight stroke and a lighter one just
  inside it, which is what a wax pencil leaves when the hand comes back around.
  Both are dashed with long dashes and hairline gaps — the gloss-skip, not a
  dashed line — and both are normalised to `pathLength="100"` so the dash
  pattern is a proportion of the ring rather than a function of how big the
  frame happens to be.

  Stroke *width* is deliberately not in these coordinates: the caller draws
  with `vector-effect: non-scaling-stroke`, so a 35mm frame and a 6x6 frame on
  the same sheet are circled by the same physical pencil.
  """

  import Bitwise

  @harmonics [2, 3, 5]
  @path_length 100

  @type stroke :: %{d: String.t(), width: float(), opacity: float(), dash: String.t()}
  @type ring :: %{viewbox: String.t(), path_length: pos_integer(), strokes: [stroke()]}

  @doc """
  A ring for a frame `w` x `h` user units, inside a box padded by `pad`.

  The box is the frame plus `pad` on every side, because the circle is drawn
  *around* the photograph and has to have somewhere to overshoot. Coordinates
  are the frame's own pixels on the sheet; the caller scales them with a
  viewBox.
  """
  @spec ring(term(), number(), number(), number()) :: ring()
  def ring(seed_term, w, h, pad) do
    box_w = w + 2 * pad
    box_h = h + 2 * pad
    state = seed(seed_term)

    # The pencil sits about on the frame's edge, cutting its corners — which is
    # what a hand actually draws. Clearing the corners properly would need a
    # radius half again as wide, and on a tight sheet that swallows the
    # neighbours. It rides unevenly, though: one side usually clears further.
    {bulge, state} = uniform(state, 0.97, 1.06)
    {skew, state} = uniform(state, 0.95, 1.05)
    {tilt, state} = uniform(state, -0.22, 0.22)
    {drift_x, state} = uniform(state, -0.018, 0.018)
    {drift_y, state} = uniform(state, -0.018, 0.018)
    {start, state} = uniform(state, 0, 2 * :math.pi())

    # A third of the time the hand goes round again rather than closing up.
    {second_lap?, state} = chance(state, 0.34)
    {overshoot, state} = uniform(state, 0.18, 0.55)
    turns = if second_lap?, do: 2.0 + overshoot, else: 1.0 + overshoot

    {wobble, state} = harmonics(state)

    centre = {box_w / 2 + drift_x * box_w, box_h / 2 + drift_y * box_h}
    radii = {w / 2 * bulge * skew, h / 2 * bulge / skew}

    {outer, state} = pass(state, centre, radii, tilt, start, turns, wobble, 1.0)

    # The return pass rides just inside the first and stops short of it.
    {inner_turns, state} = uniform(state, 0.55, 0.95)
    {inner_start, state} = uniform(state, start, start + :math.pi())
    {inner_scale, state} = uniform(state, 0.93, 0.985)

    {inner, state} =
      pass(state, centre, radii, tilt, inner_start, inner_turns, wobble, inner_scale)

    {heavy, state} = uniform(state, 1.9, 2.6)
    {light, state} = uniform(state, 0.9, 1.5)
    {dash_a, state} = uniform(state, 9.0, 19.0)
    {dash_b, _state} = uniform(state, 5.0, 11.0)

    %{
      viewbox: "0 0 #{round2(box_w)} #{round2(box_h)}",
      path_length: @path_length,
      strokes: [
        %{d: outer, width: round2(heavy), opacity: 0.92, dash: skip(dash_a, 1.4)},
        %{d: inner, width: round2(light), opacity: 0.6, dash: skip(dash_b, 2.1)}
      ]
    }
  end

  # Long dashes, hairline gaps: wax skipping on gloss, not a dashed line.
  defp skip(dash, gap), do: "#{round2(dash)} #{round2(gap)}"

  # One sweep of the pencil, sampled then smoothed. Sampling density follows
  # the sweep so a double lap is no coarser than a single one.
  defp pass(state, {cx, cy}, {rx, ry}, tilt, start, turns, wobble, scale) do
    sweep = 2 * :math.pi() * turns
    steps = max(20, round(26 * turns))
    {cos_t, sin_t} = {:math.cos(tilt), :math.sin(tilt)}

    points =
      for i <- 0..steps do
        theta = start + sweep * (i / steps)
        r = 1.0 + modulate(wobble, theta)
        # Ends taper in slightly — a stroke starts and finishes off the line.
        taper = 1.0 - 0.02 * :math.sin(:math.pi() * (i / steps))
        x = rx * scale * r * taper * :math.cos(theta)
        y = ry * scale * r * taper * :math.sin(theta)
        {cx + x * cos_t - y * sin_t, cy + x * sin_t + y * cos_t}
      end

    {to_path(points), state}
  end

  # Three harmonics at random phase and amplitude. Low orders only: higher ones
  # read as a tremor rather than as a blunt tip wandering.
  defp harmonics(state) do
    Enum.map_reduce(@harmonics, state, fn order, acc ->
      {amp, acc} = uniform(acc, 0.012, 0.042)
      {phase, acc} = uniform(acc, 0, 2 * :math.pi())
      {{order, amp, phase}, acc}
    end)
  end

  defp modulate(wobble, theta) do
    Enum.reduce(wobble, 0.0, fn {order, amp, phase}, acc ->
      acc + amp * :math.sin(order * theta + phase)
    end)
  end

  # Catmull-Rom through the samples, emitted as cubic segments. The spline
  # passes through every point, so the wobble above survives smoothing instead
  # of being averaged away.
  defp to_path([]), do: ""
  defp to_path([_single]), do: ""

  defp to_path(points) do
    pts = List.to_tuple(points)
    last = tuple_size(pts) - 1
    {x0, y0} = elem(pts, 0)

    segments =
      Enum.map_join(0..(last - 1), " ", fn i ->
        {px, py} = elem(pts, max(i - 1, 0))
        {ax, ay} = elem(pts, i)
        {bx, by} = elem(pts, i + 1)
        {qx, qy} = elem(pts, min(i + 2, last))

        c1 = {ax + (bx - px) / 6, ay + (by - py) / 6}
        c2 = {bx - (qx - ax) / 6, by - (qy - ay) / 6}

        "C #{pair(c1)} #{pair(c2)} #{pair({bx, by})}"
      end)

    "M #{pair({x0, y0})} " <> segments
  end

  defp pair({x, y}), do: "#{round2(x)},#{round2(y)}"

  defp round2(n), do: Float.round(n / 1, 2)

  # xorshift32, written out rather than taken from :rand so the sequence is
  # pure — no process state, identical on every node and after every restart.
  defp seed(term) do
    case :erlang.phash2(term, 0xFFFFFFFF) do
      0 -> 0x9E3779B9
      n -> n
    end
  end

  defp next(state) do
    s = bxor(state, state <<< 13 &&& 0xFFFFFFFF)
    s = bxor(s, s >>> 17)
    bxor(s, s <<< 5 &&& 0xFFFFFFFF)
  end

  defp uniform(state, lo, hi) do
    s = next(state)
    {lo + s / 0xFFFFFFFF * (hi - lo), s}
  end

  defp chance(state, probability) do
    s = next(state)
    {s / 0xFFFFFFFF < probability, s}
  end
end
