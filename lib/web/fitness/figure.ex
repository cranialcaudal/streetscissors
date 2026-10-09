defmodule Web.Fitness.Figure do
  @moduledoc """
  A line figure doing an exercise: the mannequin on a wiki page.

  An exercise's figure is a small JSON file beside the wiki, at
  `figures/<slug>.json` in the fitness vault. It holds a handful of **poses**
  and nothing else; this module turns them into a loop that the page plays as
  plain SVG (`WebWeb.FitnessFigure`), with no script doing the drawing.

  ## The stage

  160 units wide, the floor at y = 100, y growing downward. A standing figure
  is about 80 units tall. Things resting on the floor sit at y = 99 (a foot,
  a hand, a knee); a body lying down has its pelvis at y = 95.

  ## A pose

  A pose says where the body is, not what each joint's angle is:

    * `pelvis` `[x, y]`: the hip joint, which everything hangs from;
    * `lean`: the lower back's angle from upright, in degrees, positive
      toward the way the figure faces (right). 90 is face down with the head
      to the right, -90 is on the back with the head to the left;
    * `curl`: the upper back relative to the lower, positive rounding
      forward, negative arching; `head`: the neck, the same way;
    * `turn`: the shoulders turned about the spine, which in a side view
      slides the near shoulder back and the far one forward;
    * where each hand and foot **is**: `hand_a`/`hand_b`/`foot_a`/`foot_b` as
      `[x, y]` (or `hands`/`feet` for both at once). The elbow and knee are
      worked out so the limb reaches there. `a` is the near limb in a side
      view and the viewer's left in a front view;
    * or where a limb **points**: `arm_a`/`arm_b`/`leg_a`/`leg_b` (or
      `arms`/`legs`) as `[angle, reach]`, the angle from straight up turning
      toward the facing side, the reach a share of the limb's length. A limb
      given this way swings in an arc between poses;
    * a figure with a single pose is a hold, and stands still;
    * the figure itself may set `mirror` (face left), `floor: false` (a
      front view used as a view from above, where there is no floor to
      draw), `planted` (limbs that must not move) and `props`;
    * `elbows`/`knees` (or `elbow_a` …): which way the joint bends, one of
      `up`, `down`, `front`, `back`, `headward`, `feetward` in a side view and
      `up`, `down`, `out`, `in` in a front view;
    * `toe_a`/`toe_b`/`toes` `[x, y]`: where the foot points, for the times
      the default (flat on the floor, else square to the shin) is wrong;
    * `side`: how far the hands are to one side of the body, from 1 (the
      near side) to -1 (the far side); a flat picture cannot show it, the 3D
      clip can;
    * `spread`: how far each hand is from the middle of the body, in stage
      units, for the 3D clip: from the side, hands a shoulder's width apart
      and hands wide open look the same. Given in every pose of a figure or
      in none;
    * `flare`: how far the elbows are out to the sides, from 0 (in the
      plane of the picture) to 1 (straight out), for the 3D clip. A face pull
      drawn flat has to put the elbows above the head or below the chest;
    * `weight`: `"behind"` when what is held is on the far side of the body
      in this pose, so that the body hides it; `"front"` to bring it back. This
      is how a twist or a circle round the head reads in a flat picture;
    * `name`, `hold` (seconds spent in the pose) and `move` (seconds taken
      to reach the next one; the last pose moves back to the first).

  Because limbs are solved to reach their targets, a planted foot stays
  planted and no bone ever changes length. `build/1` refuses a figure whose
  targets cannot be reached, that goes through the floor or off the stage,
  whose joints flip sides between poses, or that names a key it does not
  know, and says which pose. Nothing is drawn from a file that fails.
  """

  alias Web.Fitness.Vault

  @width 160.0
  @height 108
  @floor 100.0
  @rest 99.0

  # Where the floor is drawn. A joint rests at y = 99; the body round it has
  # thickness, so the line it stands on is a little lower, and the figure is
  # clipped there: a knee or a hip on the floor is flattened by it, as a body
  # with weight is.
  @ground 101.2

  # How thick each part is drawn. The figure is a body, not a wire: the trunk
  # is a tenth of its height deep, a thigh is thicker than a shin.
  @thick %{
    belly: 10.5,
    chest: 12.0,
    neck: 4.2,
    thigh: 7.6,
    shin: 5.6,
    foot: 4.2,
    upper_arm: 5.2,
    forearm: 4.3,
    trunk_edge: 5.0
  }
  @hand_r 2.6
  @collar 4.5

  @head_r 5.6
  @neck 3.0
  @spine_lo 13.0
  @spine_up 13.0
  @upper_arm 14.0
  @forearm 15.0
  @thigh 20.0
  @shin 20.0
  @foot 7.0
  @foot_front 4.0
  @shoulder_half 8.0
  @hip_half 5.0

  @fps 12

  @side_bends ~w(up down front back headward feetward)
  @front_bends ~w(up down out in)
  @limbs [:arm_a, :arm_b, :leg_a, :leg_b]
  @holds ~w(hands hand_a hand_b)
  @line_ends ~w(hands hand_a hand_b foot_a foot_b)
  @pose_keys ~w(name hold move pelvis lean curl head turn hands hand_a hand_b arms arm_a arm_b
                feet foot_a foot_b legs leg_a leg_b toes toe_a toe_b elbows elbow_a elbow_b
                knees knee_a knee_b weight side spread flare)
  @top_keys ~w(view mirror floor planted props poses note targets model)

  @muscle_map [
    {~r/\b(?:quads?|quadriceps)\b/i, :quads},
    {~r/\b(?:glutes?|gluteal|gluteus)\b/i, :glutes},
    {~r/\b(?:hamstrings?)\b/i, :hamstrings},
    {~r/\b(?:calves?|gastrocnemius|soleus)\b/i, :calves},
    {~r/\b(?:chest|pectorals?|pecs?)\b/i, :chest},
    {~r/\b(?:back|lats?|latissimus|rhomboids?|traps?|trapezius)\b/i, :back},
    {~r/\b(?:deltoids?|delts?|shoulders?)\b/i, :deltoids},
    {~r/\b(?:biceps?)\b/i, :biceps},
    {~r/\b(?:triceps?)\b/i, :triceps},
    {~r/\b(?:forearms?|brachioradialis|grip)\b/i, :forearms},
    {~r/\b(?:core|abdominals?|abs?|obliques?|rectus\s+abdominis|transverse\s+abdominis)\b/i,
     :core}
  ]

  @doc "Detects targeted muscle groups from exercise vault metadata."
  def detect_targets(nil), do: []

  def detect_targets(slug) when is_binary(slug) do
    case Vault.get_exercise_by_slug(slug) do
      {:ok, ex} ->
        text = "#{ex[:anatomy] || ex.anatomy} #{ex[:muscle_group] || ex.muscle_group}"

        targets =
          for {regex, muscle} <- @muscle_map, Regex.match?(regex, text) do
            muscle
          end

        Enum.uniq(targets)

      _ ->
        []
    end
  end

  @doc "The stage a figure is drawn on, for the component's `viewBox`."
  def stage, do: %{width: trunc(@width), height: @height, floor: @ground}

  @doc "Where an exercise's figure file would be."
  def path(slug), do: Path.join([Vault.base_path(), "figures", slug <> ".json"])

  @doc """
  The figure for an exercise: `{:ok, figure}`, `:none` when the exercise has
  no file, or `{:error, problems}` when the file is there and wrong.
  """
  def load(slug) do
    case File.read(path(slug)) do
      {:ok, json} -> from_json(json, slug)
      {:error, _} -> :none
    end
  end

  @doc "Every figure file in the vault, as `{slug, load(slug)}`."
  def all do
    dir = Path.join(Vault.base_path(), "figures")

    case File.ls(dir) do
      {:ok, files} ->
        for file <- Enum.sort(files), String.ends_with?(file, ".json") do
          slug = Path.basename(file, ".json")
          {slug, load(slug)}
        end

      _ ->
        []
    end
  end

  def from_json(json, slug \\ nil) do
    case Jason.decode(json) do
      {:ok, %{} = raw} -> build(raw, slug)
      {:ok, _} -> {:error, ["the file is not a JSON object"]}
      {:error, error} -> {:error, ["not valid JSON: " <> Exception.message(error)]}
    end
  end

  @doc """
  Builds the loop from a decoded figure. Returns `{:ok, figure}` or
  `{:error, problems}`, each problem a sentence naming the pose it is in.

  A figure is `%{view, seconds, frames, stops, box, back, top, props}`. `back`
  and `top` are the layers of the body in drawing order, each with its parts
  (`%{w, d}`: a thickness and one path per frame), and `props` what is held
  or stood on. Every list of values has one entry per frame, the last
  repeating the first so the loop closes, ready to be SMIL `values`.
  """
  def build(raw, slug \\ nil) when is_map(raw) do
    with {:ok, spec} <- parse(raw, slug),
         {:ok, keys} <- solve_poses(spec),
         {:ok, frames} <- frames(spec, keys, @fps) do
      {:ok, bake(spec, keys, frames)}
    end
  end

  @doc """
  The same loop as raw joints, for a renderer that draws the figure some other
  way than this module's SVG (`Web.Fitness.Clip`, which films it in 3D).

  `{:ok, track}`: `frames` is one map per frame at `fps`, each joint an
  `[x, y]` on the stage, with the shoulders' `turn` and the hands' `side`;
  `props` are as written, the held ones with where they are gripped and where
  their weight sits in every frame. The closing frame is left off: a clip
  loops by starting again.
  """
  def track(raw, fps \\ 24) when is_map(raw) do
    with {:ok, spec} <- parse(raw, nil),
         {:ok, keys} <- solve_poses(spec),
         {:ok, frames} <- frames(spec, keys, fps) do
      {stops, _} =
        Enum.map_reduce(keys, 0.0, fn pose, at ->
          {%{name: pose.name, at: Float.round(at, 2)}, at + pose.hold + pose.move}
        end)

      # A hold is filmed as it stands; a loop leaves off the frame that repeats.
      joints = if length(keys) == 1, do: frames.joints, else: Enum.drop(frames.joints, -1)

      {:ok,
       %{
         view: spec.view,
         floor: spec.floor,
         mirror: spec.mirror,
         seconds: Float.round(frames.seconds * 1.0, 3),
         fps: fps,
         stops: stops,
         frames: Enum.map(joints, &track_frame/1),
         props: Enum.map(spec.props, &track_prop(&1, joints))
       }}
    end
  end

  @track_joints ~w(pelvis chest neck nape head sh_a sh_b hip_a hip_b elbow_a elbow_b hand_a hand_b
                   knee_a knee_b foot_a foot_b toe_a toe_b)a

  defp track_frame(joints) do
    @track_joints
    |> Map.new(fn key -> {key, pair(Map.fetch!(joints, key))} end)
    |> Map.merge(%{
      turn: Float.round(joints.turn * 1.0, 2),
      side: Float.round(joints.lateral * 1.0, 3),
      spread: joints.spread && Float.round(joints.spread * 1.0, 2),
      flare: Float.round(joints.flare * 1.0, 3)
    })
  end

  defp pair({x, y}), do: [Float.round(x * 1.0, 2), Float.round(y * 1.0, 2)]

  defp track_prop(%{hold: hold} = prop, frames) do
    places =
      Enum.map(frames, fn frame ->
        {grip, weight} = grip_and_weight(prop, frame)
        [pair(grip), pair(weight)]
      end)

    %{kind: prop.kind, hold: hold, mode: prop.mode, at: places}
  end

  defp track_prop(%{kind: :line} = line, frames) do
    place = fn
      {_, _} = fixed, _frame -> fixed
      :hands, frame -> mid(frame.hand_a, frame.hand_b)
      limb, frame -> Map.fetch!(frame, limb)
    end

    ends = fn spot -> if is_atom(spot), do: spot, else: :fixed end

    %{
      kind: :line,
      style: line.style,
      depth: line.depth,
      ends: [ends.(line.from), ends.(line.to)],
      at:
        Enum.map(frames, fn frame ->
          [pair(place.(line.from, frame)), pair(place.(line.to, frame))]
        end)
    }
  end

  defp track_prop(%{kind: :disc, at: at} = disc, _frames), do: %{disc | at: pair(at)}
  defp track_prop(prop, _frames), do: prop

  # ── Reading the file ─────────────────────────────────────────────────

  defp parse(raw, slug) do
    view = Map.get(raw, "view", "side")
    poses = Map.get(raw, "poses")

    explicit_targets =
      case Map.get(raw, "targets") do
        targets when is_list(targets) ->
          Enum.map(targets, fn
            t when is_binary(t) -> String.to_atom(t)
            t when is_atom(t) -> t
          end)

        _ ->
          nil
      end

    targets = explicit_targets || detect_targets(slug)

    problems =
      unknown_keys(raw, @top_keys, "the figure") ++
        if(view in ~w(side front), do: [], else: ["view must be \"side\" or \"front\""]) ++
        if(is_list(poses) and poses != [],
          do: [],
          else: ["a figure needs at least one pose"]
        )

    if problems != [] do
      {:error, problems}
    else
      view = String.to_existing_atom(view)

      parsed =
        poses |> Enum.with_index(1) |> Enum.map(fn {pose, n} -> parse_pose(pose, n, view) end)

      {props, prop_problems} = parse_props(Map.get(raw, "props", []))
      planted = Map.get(raw, "planted", [])

      problems =
        Enum.flat_map(parsed, &elem(&1, 1)) ++ prop_problems ++ planted_problems(planted, parsed)

      if problems == [] do
        {:ok,
         %{
           view: view,
           mirror: Map.get(raw, "mirror", false) == true,
           floor: Map.get(raw, "floor", true) != false,
           props: props,
           poses: Enum.map(parsed, &elem(&1, 0)),
           targets: targets
         }}
      else
        {:error, problems}
      end
    end
  end

  defp unknown_keys(map, known, where) do
    for key <- Map.keys(map), key not in known, do: "#{where} has a key it does not know: #{key}"
  end

  defp parse_pose(pose, n, _view) when not is_map(pose),
    do: {nil, ["pose #{n} is not an object"]}

  defp parse_pose(pose, n, view) do
    name = if is_binary(pose["name"]), do: pose["name"], else: "pose #{n}"
    where = "pose \"#{name}\""
    bends = if view == :side, do: @side_bends, else: @front_bends

    {arm_a, p1} = limb(pose, "hand_a", "hands", "arm_a", "arms", where)
    {arm_b, p2} = limb(pose, "hand_b", "hands", "arm_b", "arms", where)
    {leg_a, p3} = limb(pose, "foot_a", "feet", "leg_a", "legs", where)
    {leg_b, p4} = limb(pose, "foot_b", "feet", "leg_b", "legs", where)

    {elbow_default, knee_default} = if view == :side, do: {"back", "front"}, else: {"out", "out"}
    {elbow_a, p5} = bend(pose, "elbow_a", "elbows", elbow_default, bends, where)
    {elbow_b, p6} = bend(pose, "elbow_b", "elbows", elbow_default, bends, where)
    {knee_a, p7} = bend(pose, "knee_a", "knees", knee_default, bends, where)
    {knee_b, p8} = bend(pose, "knee_b", "knees", knee_default, bends, where)

    {pelvis, p9} = point(pose["pelvis"], where, "pelvis", :required)
    {toe_a, p10} = point(pose["toe_a"] || pose["toes"], where, "toe_a", :optional)
    {toe_b, p11} = point(pose["toe_b"] || pose["toes"], where, "toe_b", :optional)

    numbers =
      for key <- ~w(lean curl head turn side spread flare hold move),
          not is_nil(pose[key]),
          not is_number(pose[key]) do
        "#{where}: #{key} must be a number"
      end

    {weight, p12} =
      case pose["weight"] do
        nil -> {nil, []}
        "front" -> {:front, []}
        "behind" -> {:behind, []}
        _ -> {nil, ["#{where}: weight must be \"front\" or \"behind\""]}
      end

    name_problem = if is_binary(pose["name"]), do: [], else: ["pose #{n} has no name"]
    move = num(pose["move"], 1.0)
    hold = num(pose["hold"], 0.3)

    timing =
      if(move < 0.2, do: ["#{where}: move must be at least 0.2 seconds"], else: []) ++
        if hold < 0, do: ["#{where}: hold cannot be negative"], else: []

    parsed = %{
      name: name,
      hold: hold,
      move: move,
      pelvis: pelvis,
      lean: num(pose["lean"], 0.0),
      curl: num(pose["curl"], 0.0),
      head: num(pose["head"], 0.0),
      turn: num(pose["turn"], 0.0),
      side: num(pose["side"], 0.0),
      spread: if(is_number(pose["spread"]), do: pose["spread"] * 1.0),
      flare: num(pose["flare"], 0.0),
      arm_a: arm_a,
      arm_b: arm_b,
      leg_a: leg_a,
      leg_b: leg_b,
      toe_a: toe_a,
      toe_b: toe_b,
      weight: weight,
      bend: %{arm_a: elbow_a, arm_b: elbow_b, leg_a: knee_a, leg_b: knee_b}
    }

    problems =
      unknown_keys(pose, @pose_keys, where) ++
        name_problem ++
        numbers ++
        timing ++ p1 ++ p2 ++ p3 ++ p4 ++ p5 ++ p6 ++ p7 ++ p8 ++ p9 ++ p10 ++ p11 ++ p12

    {parsed, problems}
  end

  defp num(value, _default) when is_number(value), do: value * 1.0
  defp num(_value, default), do: default

  # A limb is given either as where its end is (`[x, y]`) or as where it
  # points from its root (`[angle, reach]`).
  defp limb(pose, xy_key, xy_both, polar_key, polar_both, where) do
    xy = pose[xy_key] || pose[xy_both]
    polar = pose[polar_key] || pose[polar_both]

    case {xy, polar} do
      {[x, y], nil} when is_number(x) and is_number(y) ->
        {{:xy, {x * 1.0, y * 1.0}}, []}

      {nil, [angle, reach]}
      when is_number(angle) and is_number(reach) and reach > 0 and reach <= 1 ->
        {{:polar, angle * 1.0, reach * 1.0}, []}

      {nil, nil} ->
        {nil,
         [
           "#{where} does not say where #{xy_key} is (#{xy_key}, #{xy_both}, #{polar_key} or #{polar_both})"
         ]}

      {nil, _} ->
        {nil, ["#{where}: #{polar_key} must be [angle, reach] with reach between 0 and 1"]}

      {_, nil} ->
        {nil, ["#{where}: #{xy_key} must be [x, y]"]}

      _ ->
        {nil, ["#{where} gives #{xy_key} both as a place and as a direction; choose one"]}
    end
  end

  defp bend(pose, key, both, default, allowed, where) do
    value = pose[key] || pose[both] || default

    if value in allowed do
      {String.to_existing_atom(value), []}
    else
      {:down, ["#{where}: #{key} must be one of #{Enum.join(allowed, ", ")}"]}
    end
  end

  defp point([x, y], _where, _key, _need) when is_number(x) and is_number(y),
    do: {{x * 1.0, y * 1.0}, []}

  defp point(nil, _where, _key, :optional), do: {nil, []}
  defp point(nil, where, key, :required), do: {nil, ["#{where} has no #{key}"]}
  defp point(_other, where, key, _need), do: {nil, ["#{where}: #{key} must be [x, y]"]}

  defp parse_props(props) when is_list(props) do
    parsed = props |> Enum.with_index(1) |> Enum.map(fn {prop, n} -> parse_prop(prop, n) end)
    {for({prop, []} <- parsed, do: prop), Enum.flat_map(parsed, &elem(&1, 1))}
  end

  defp parse_props(_props), do: {[], ["props must be a list"]}

  defp parse_prop(%{"kind" => kind} = prop, n) when kind in ~w(kettlebell dumbbell ball bar) do
    hold = Map.get(prop, "hold", "hands")
    mode = Map.get(prop, "mode", "hang")

    cond do
      hold not in @holds ->
        {nil, ["prop #{n}: hold must be one of #{Enum.join(@holds, ", ")}"]}

      mode not in ~w(hang arm up) ->
        {nil, ["prop #{n}: mode must be hang, arm or up"]}

      true ->
        {%{
           kind: String.to_existing_atom(kind),
           hold: String.to_existing_atom(hold),
           mode: String.to_existing_atom(mode)
         }, unknown_keys(prop, ~w(kind hold mode), "prop #{n}")}
    end
  end

  defp parse_prop(%{"kind" => "mat"} = prop, n) do
    case {prop["from"], prop["to"]} do
      {from, to} when is_number(from) and is_number(to) and to > from ->
        {%{kind: :mat, from: from * 1.0, to: to * 1.0},
         unknown_keys(prop, ~w(kind from to), "prop #{n}")}

      _ ->
        {nil, ["prop #{n}: a mat needs from and to, with to greater than from"]}
    end
  end

  defp parse_prop(%{"kind" => "box"} = prop, n) do
    case {prop["x"], prop["w"], prop["h"]} do
      {x, w, h} when is_number(x) and is_number(w) and is_number(h) and w > 0 and h > 0 ->
        {%{kind: :box, x: x * 1.0, w: w * 1.0, h: h * 1.0},
         unknown_keys(prop, ~w(kind x w h), "prop #{n}")}

      _ ->
        {nil, ["prop #{n}: a box needs x, w and h"]}
    end
  end

  # A rectangle anywhere on the stage: a bench, a wall, a hanging bag, the
  # surface of the water. `y` is its top edge.
  defp parse_prop(%{"kind" => "block"} = prop, n) do
    case {prop["x"], prop["y"], prop["w"], prop["h"]} do
      {x, y, w, h}
      when is_number(x) and is_number(y) and is_number(w) and is_number(h) and w > 0 and h > 0 ->
        {%{kind: :block, x: x * 1.0, y: y * 1.0, w: w * 1.0, h: h * 1.0},
         unknown_keys(prop, ~w(kind x y w h), "prop #{n}")}

      _ ->
        {nil, ["prop #{n}: a block needs x, y, w and h"]}
    end
  end

  # A fixed circle: a bar seen end-on, a roller, a small bag.
  defp parse_prop(%{"kind" => "disc"} = prop, n) do
    case {prop["at"], Map.get(prop, "r", 2.4)} do
      {[x, y], r} when is_number(x) and is_number(y) and is_number(r) and r > 0 ->
        # `ball` tells the 3D clip the disc is round every way (a hanging
        # bag), not the end of something lying across (a roller, a bar)
        {%{kind: :disc, at: {x * 1.0, y * 1.0}, r: r * 1.0, ball: prop["ball"] == true},
         unknown_keys(prop, ~w(kind at r ball), "prop #{n}")}

      _ ->
        {nil, ["prop #{n}: a disc needs at: [x, y]"]}
    end
  end

  # The half-ball of a BOSU, standing on the floor; `x` is its middle.
  defp parse_prop(%{"kind" => "dome"} = prop, n) do
    case {prop["x"], Map.get(prop, "w", 30), Map.get(prop, "h", 9)} do
      {x, w, h} when is_number(x) and is_number(w) and is_number(h) and w > 0 and h > 0 ->
        {%{kind: :dome, x: x * 1.0, w: w * 1.0, h: h * 1.0},
         unknown_keys(prop, ~w(kind x w h), "prop #{n}")}

      _ ->
        {nil, ["prop #{n}: a dome needs x"]}
    end
  end

  # A line between two ends, each a fixed place or a hand or foot: a band or
  # cable from its anchor, a bar hinged at the floor, the slope of a bench.
  # `depth` is how far toward the viewer its fixed end is, for the 3D clip: a
  # band that comes from beside the body cannot be drawn flat.
  defp parse_prop(%{"kind" => "line"} = prop, n) do
    style = Map.get(prop, "style", "band")
    ends = [line_end(prop["from"]), line_end(prop["to"])]

    cond do
      style not in ~w(band pole) ->
        {nil, ["prop #{n}: a line's style is band or pole"]}

      :error in ends ->
        {nil,
         [
           "prop #{n}: a line's from and to are each [x, y] or one of #{Enum.join(@line_ends, ", ")}"
         ]}

      not is_number(Map.get(prop, "depth", 0)) ->
        {nil, ["prop #{n}: a line's depth must be a number"]}

      true ->
        [from, to] = ends

        {%{
           kind: :line,
           from: from,
           to: to,
           style: if(style == "pole", do: :pole, else: :band),
           depth: Map.get(prop, "depth", 0) * 1.0
         }, unknown_keys(prop, ~w(kind from to style depth), "prop #{n}")}
    end
  end

  defp parse_prop(_prop, n),
    do:
      {nil,
       [
         "prop #{n} must have a kind: kettlebell, dumbbell, ball, bar, mat, box, block, disc, dome or line"
       ]}

  defp line_end([x, y]) when is_number(x) and is_number(y), do: {x * 1.0, y * 1.0}
  defp line_end(name) when name in @line_ends, do: String.to_existing_atom(name)
  defp line_end(_other), do: :error

  # A planted limb is one the file promises never moves, so its place must be
  # the same in every pose.
  defp planted_problems(planted, _parsed) when not is_list(planted),
    do: ["planted must be a list"]

  defp planted_problems(planted, parsed) do
    poses = for {pose, _} <- parsed, pose != nil, do: pose

    Enum.flat_map(planted, fn name ->
      key =
        case name do
          "hand_a" -> :arm_a
          "hand_b" -> :arm_b
          "foot_a" -> :leg_a
          "foot_b" -> :leg_b
          _ -> nil
        end

      places = if key, do: poses |> Enum.map(&Map.get(&1, key)) |> Enum.uniq(), else: []

      cond do
        is_nil(key) ->
          ["planted names #{inspect(name)}; it takes hand_a, hand_b, foot_a, foot_b"]

        Enum.any?(places, &(not match?({:xy, _}, &1))) ->
          ["#{name} is planted, so every pose must give it as [x, y]"]

        length(places) > 1 ->
          ["#{name} is planted but is not in the same place in every pose"]

        true ->
          []
      end
    end)
  end

  # ── Solving a pose ───────────────────────────────────────────────────

  # Each pose is solved once on its own, which settles which side every elbow
  # and knee bends to. The frames in between are then solved holding those
  # sides, so a joint cannot flicker across its limb mid-move.
  defp solve_poses(spec) do
    solved =
      Enum.map(spec.poses, fn pose ->
        joints = solve(spec.view, pose, nil)
        Map.put(pose, :joints, joints)
      end)

    problems =
      Enum.flat_map(solved, fn pose ->
        reach_problems(pose) ++ place_problems(pose.joints, "pose \"#{pose.name}\"", spec.floor)
      end) ++
        flip_problems(solved)

    if problems == [], do: {:ok, solved}, else: {:error, problems}
  end

  defp reach_problems(pose) do
    for limb <- @limbs, miss = pose.joints.miss[limb], abs(miss) > 0.6 do
      what =
        limb |> Atom.to_string() |> String.replace("arm", "hand") |> String.replace("leg", "foot")

      if miss > 0 do
        "pose \"#{pose.name}\": #{what} is #{Float.round(miss, 1)} units out of reach"
      else
        "pose \"#{pose.name}\": #{what} is #{Float.round(-miss, 1)} units too close to its root for the limb to fold"
      end
    end
  end

  # A figure with no floor (hanging from a bar, swimming, seen from above) is
  # held only to the stage.
  defp place_problems(joints, where, floor) do
    points =
      for key <-
            ~w(pelvis chest neck elbow_a elbow_b hand_a hand_b knee_a knee_b foot_a foot_b toe_a toe_b)a do
        {key, Map.fetch!(joints, key)}
      end

    {hx, hy} = joints.head
    bottom = if floor, do: @ground + 0.6, else: @height - 1.0

    below =
      for {key, {_x, y}} <- points,
          floor and y > @rest + 0.6,
          do: "#{where}: #{key} is below the floor"

    off =
      for {key, {x, y}} <- points,
          x < 1 or x > @width - 1 or y < 1 or y > @height - 1,
          do: "#{where}: #{key} is off the stage"

    head =
      cond do
        floor and hy + @head_r > bottom ->
          ["#{where}: the head is through the floor"]

        hy - @head_r < 0 or hx - @head_r < 0 or hx + @head_r > @width or hy + @head_r > @height ->
          ["#{where}: the head is off the stage"]

        true ->
          []
      end

    Enum.uniq(below ++ off ++ head)
  end

  # A joint that bends one way in a pose and the other way in the next pops
  # across its limb on the way. That only shows when the limb is bent in both.
  defp flip_problems(solved) do
    pairs = Enum.zip(solved, tl(solved) ++ [hd(solved)])

    for {from, to} <- pairs,
        limb <- @limbs,
        from.joints.side[limb] != to.joints.side[limb],
        from.joints.bent[limb] > 1.5 and to.joints.bent[limb] > 1.5 do
      joint = if limb in [:arm_a, :arm_b], do: "elbow", else: "knee"
      side = limb |> Atom.to_string() |> String.last()

      "#{joint}_#{side} bends one way in \"#{from.name}\" and the other in \"#{to.name}\"; say which way it bends in both"
    end
  end

  # `sides` is nil for a pose solved on its own, or the sides to hold.
  defp solve(view, pose, sides) do
    spine = pose.lean + pose.curl
    chest = add(pose.pelvis, mul(dir(pose.lean), @spine_lo))
    neck = add(chest, mul(dir(spine), @spine_up))
    crown = dir(spine + pose.head)
    head = add(neck, mul(crown, @neck + @head_r))

    across_lo = dir(pose.lean + 90)
    across_up = dir(spine + 90)
    turn = pose.turn * :math.pi() / 180

    {sh_a, sh_b, hip_a, hip_b} =
      case view do
        :side ->
          slide = mul(across_up, @shoulder_half * :math.sin(turn))
          {sub(neck, slide), add(neck, slide), pose.pelvis, pose.pelvis}

        :front ->
          half = mul(across_up, @shoulder_half * :math.cos(turn))
          hips = mul(across_lo, @hip_half)
          {sub(neck, half), add(neck, half), sub(pose.pelvis, hips), add(pose.pelvis, hips)}
      end

    refs = %{
      front: across_up,
      feetward: mul(dir(spine), -1.0),
      out_a: mul(across_up, -1.0),
      out_b: across_up
    }

    # A knee's "front" is the way the figure faces while it is on its feet,
    # however far the back is tipped, and the body's own front once it is
    # lying down. Taking it from the pelvis alone bends the knees backward in
    # a deep hinge, where the pelvis's front points at the floor.
    lying = ease(clamp((abs(pose.lean) - 60) / 30))
    knee_front = unit(add(mul({1.0, 0.0}, 1 - lying), mul(across_lo, lying)))

    leg_refs = %{
      refs
      | front: if(view == :side, do: knee_front, else: across_lo),
        feetward: mul(dir(pose.lean), -1.0),
        out_a: mul(across_lo, -1.0),
        out_b: across_lo
    }

    limbs = [
      {:arm_a, sh_a, @upper_arm, @forearm, refs, :out_a},
      {:arm_b, sh_b, @upper_arm, @forearm, refs, :out_b},
      {:leg_a, hip_a, @thigh, @shin, leg_refs, :out_a},
      {:leg_b, hip_b, @thigh, @shin, leg_refs, :out_b}
    ]

    reached =
      Map.new(limbs, fn {limb, root, upper, lower, limb_refs, out} ->
        target = target(Map.fetch!(pose, limb), root, upper + lower)
        want = sides && sides[limb]
        {limb, reach(root, target, upper, lower, pose.bend[limb], limb_refs, out, want)}
      end)

    toe_a = toe(view, :a, reached.leg_a, pose[:toe_a], pose[:toe_from_a])
    toe_b = toe(view, :b, reached.leg_b, pose[:toe_b], pose[:toe_from_b])

    %{
      pelvis: pose.pelvis,
      chest: chest,
      neck: neck,
      nape: add(neck, mul(crown, @neck)),
      collar: sub(neck, mul(dir(spine), @collar)),
      head: head,
      weight: pose[:weight],
      turn: pose.turn,
      lateral: pose[:side] || 0.0,
      spread: pose[:spread],
      flare: pose[:flare] || 0.0,
      sh_a: sh_a,
      sh_b: sh_b,
      hip_a: hip_a,
      hip_b: hip_b,
      elbow_a: reached.arm_a.joint,
      elbow_b: reached.arm_b.joint,
      hand_a: reached.arm_a.tip,
      hand_b: reached.arm_b.tip,
      knee_a: reached.leg_a.joint,
      knee_b: reached.leg_b.joint,
      foot_a: reached.leg_a.tip,
      foot_b: reached.leg_b.tip,
      toe_a: toe_a,
      toe_b: toe_b,
      side: Map.new(reached, fn {limb, r} -> {limb, r.side} end),
      bent: Map.new(reached, fn {limb, r} -> {limb, r.bent} end),
      miss: Map.new(reached, fn {limb, r} -> {limb, r.miss} end)
    }
  end

  defp target({:xy, point}, _root, _length), do: point

  defp target({:polar, angle, share}, root, length),
    do: add(root, mul(dir(angle), share * length))

  # Two bones from `root` to `target`: where the joint between them goes.
  # `miss` is how far the target is beyond the limb's reach (or, negative,
  # inside what it can fold to); the tip is then as near as the limb gets.
  defp reach(root, target, upper, lower, bend, refs, out, want) do
    gap = len(sub(target, root))
    span = gap |> max(abs(upper - lower) + 0.01) |> min(upper + lower - 0.01)
    toward = unit(sub(target, root))

    along = (upper * upper - lower * lower + span * span) / (2 * span)

    # A limb within a few percent of straight is drawn straight. Near full
    # reach the joint's height off the limb's line is very sensitive to the
    # distance (a leg 1% short of straight shows a knee 3 units proud), so a
    # planted foot under a pivoting body would otherwise wobble at the knee.
    slack = 1.0 - ease(clamp((span / (upper + lower) - 0.94) / 0.05))
    rise = :math.sqrt(max(upper * upper - along * along, 0.0)) * slack
    {tx, ty} = toward
    square = {-ty, tx}

    side =
      want ||
        case bend do
          :down -> sign(elem(square, 1))
          :up -> -sign(elem(square, 1))
          :front -> sign(dot(square, refs.front))
          :back -> -sign(dot(square, refs.front))
          :feetward -> sign(dot(square, refs.feetward))
          :headward -> -sign(dot(square, refs.feetward))
          :out -> sign(dot(square, Map.fetch!(refs, out)))
          :in -> -sign(dot(square, Map.fetch!(refs, out)))
        end

    %{
      joint: root |> add(mul(toward, along)) |> add(mul(square, rise * side)),
      tip: add(root, mul(toward, span)),
      side: side,
      bent: rise,
      miss:
        cond do
          gap > upper + lower -> gap - (upper + lower)
          gap < abs(upper - lower) -> gap - abs(upper - lower)
          true -> 0.0
        end
    }
  end

  defp sign(value) when value < 0, do: -1
  defp sign(_value), do: 1

  # A foot is square to its shin, toes forward, unless that would put the
  # toes through the floor, in which case it lies along the floor. `given` is
  # a place the file names; `from` is the foot's own direction carried over
  # from the poses either side of a frame.
  defp toe(_view, _which, leg, _given, {fx, fy}) do
    {ax, ay} = leg.tip

    # Halfway between two poses the ankle may be lower than in either while
    # the foot still points down: the toes stop at the floor.
    if ay + fy > @rest do
      drop = max(@rest - ay, 0.0)
      length = :math.sqrt(fx * fx + fy * fy)
      {ax + sign(fx) * :math.sqrt(max(length * length - drop * drop, 0.0)), ay + drop}
    else
      {ax + fx, ay + fy}
    end
  end

  defp toe(:front, which, leg, nil, nil) do
    {_x, y} = leg.tip

    if y > @rest - 4 do
      add(leg.tip, {if(which == :a, do: -@foot_front, else: @foot_front), 0.0})
    else
      add(leg.tip, mul(unit(sub(leg.tip, leg.joint)), @foot_front))
    end
  end

  defp toe(:side, _which, leg, nil, nil) do
    {sx, sy} = unit(sub(leg.tip, leg.joint))
    {px, py} = {sy, -sx}
    {ax, ay} = leg.tip

    if ay + py * @foot > @rest do
      drop = max(@rest - ay, 0.0)
      run = :math.sqrt(max(@foot * @foot - drop * drop, 0.0))
      forward = if abs(px) > 0.2, do: sign(px), else: sign(sx)
      {ax + forward * run, ay + drop}
    else
      {ax + px * @foot, ay + py * @foot}
    end
  end

  defp toe(view, _which, leg, given, nil) do
    length = if view == :side, do: @foot, else: @foot_front
    add(leg.tip, mul(unit(sub(given, leg.tip)), length))
  end

  # ── The frames between poses ─────────────────────────────────────────

  # A hold is a single pose: nothing moves, so it is two still seconds.
  defp frames(_spec, [only], fps),
    do:
      {:ok,
       %{seconds: 2.0, joints: List.duplicate(only.joints, max(round(2.0 * fps / 12) * 1 + 1, 2))}}

  defp frames(spec, keys, fps) do
    total = keys |> Enum.map(&(&1.hold + &1.move)) |> Enum.sum()

    if total < 0.6 or total > 12 do
      {:error,
       ["the loop lasts #{Float.round(total, 1)} seconds; it should be between 0.6 and 12"]}
    else
      count = round(total * fps)
      pairs = Enum.zip(keys, tl(keys) ++ [hd(keys)])

      frames =
        for n <- 0..(count - 1) do
          {from, to, share} = locate(pairs, n * total / count)
          {between(spec, from, to, ease(share)), from.name, to.name}
        end

      problems =
        frames
        |> Enum.flat_map(fn {joints, from, to} ->
          place_problems(joints, "between \"#{from}\" and \"#{to}\"", spec.floor)
        end)
        |> Enum.uniq()

      if problems == [] do
        {:ok, %{seconds: total, joints: Enum.map(frames, &elem(&1, 0))}}
      else
        {:error, problems}
      end
    end
  end

  # Which pair of poses a moment falls between, and how far along (0 while
  # the first is still being held).
  defp locate([{from, to} | rest], time) do
    cond do
      time < from.hold ->
        {from, to, 0.0}

      time < from.hold + from.move or rest == [] ->
        {from, to, min((time - from.hold) / from.move, 1.0)}

      true ->
        locate(rest, time - from.hold - from.move)
    end
  end

  defp ease(share), do: share * share * (3 - 2 * share)
  defp clamp(value), do: value |> max(0.0) |> min(1.0)

  defp between(_spec, from, _to, share) when share == 0.0, do: from.joints

  defp between(%{view: view, floor: floor}, from, to, share) do
    mix = fn a, b -> a + (b - a) * share end
    mix_point = fn {ax, ay}, {bx, by} -> {mix.(ax, bx), mix.(ay, by)} end

    limbs =
      Map.new(@limbs, fn limb ->
        tip =
          if limb in [:arm_a, :arm_b],
            do: String.to_existing_atom("hand_" <> suffix(limb)),
            else: String.to_existing_atom("foot_" <> suffix(limb))

        value =
          case {Map.fetch!(from, limb), Map.fetch!(to, limb)} do
            {{:polar, a1, r1}, {:polar, a2, r2}} -> {:polar, mix.(a1, a2), mix.(r1, r2)}
            _ -> {:xy, mix_point.(Map.fetch!(from.joints, tip), Map.fetch!(to.joints, tip))}
          end

        {limb, value}
      end)

    foot_dir = fn which ->
      toe = String.to_existing_atom("toe_" <> which)
      foot = String.to_existing_atom("foot_" <> which)
      a = sub(Map.fetch!(from.joints, toe), Map.fetch!(from.joints, foot))
      b = sub(Map.fetch!(to.joints, toe), Map.fetch!(to.joints, foot))
      length = if view == :side, do: @foot, else: @foot_front
      mul(unit(mix_point.(a, b)), length)
    end

    pose =
      Map.merge(limbs, %{
        pelvis: mix_point.(from.pelvis, to.pelvis),
        lean: mix.(from.lean, to.lean),
        curl: mix.(from.curl, to.curl),
        head: mix.(from.head, to.head),
        turn: mix.(from.turn, to.turn),
        side: mix.(from.side, to.side),
        spread: if(from.spread && to.spread, do: mix.(from.spread, to.spread)),
        flare: mix.(from.flare, to.flare),
        bend: from.bend,
        weight: if(share < 0.5, do: from.weight, else: to.weight),
        toe_from_a: foot_dir.("a"),
        toe_from_b: foot_dir.("b")
      })

    sides = if share < 0.5, do: from.joints.side, else: to.joints.side
    joints = solve(view, pose, sides)
    if floor, do: ride_up(view, pose, sides, joints, 4), else: joints
  end

  # A body rocking over its knees pivots on them, so the hips travel an arc.
  # The straight line between two poses cuts under that arc and would press
  # the knees into the floor; the floor pushes back and the pelvis rides up.
  defp ride_up(_view, _pose, _sides, joints, 0), do: joints

  defp ride_up(view, pose, sides, joints, tries) do
    {_x, ya} = joints.knee_a
    {_x, yb} = joints.knee_b
    sunk = max(ya, yb) - @rest

    if sunk > 0.05 do
      {px, py} = pose.pelvis
      pose = %{pose | pelvis: {px, py - sunk}}
      ride_up(view, pose, sides, solve(view, pose, sides), tries - 1)
    else
      joints
    end
  end

  defp suffix(limb), do: limb |> Atom.to_string() |> String.last()

  # ── Baking ───────────────────────────────────────────────────────────

  # The figure is drawn back to front in layers, each a group of parts that
  # share a tone: the far limbs (dim), the trunk and head, then the near
  # limbs, which carry a dark edge so an arm reads against the body it
  # crosses. What is held goes behind everything or in front of the near leg,
  # frame by frame; the arms on the near side are drawn over it.
  defp bake(spec, keys, %{seconds: seconds, joints: joints}) do
    frames = joints ++ [hd(joints)]
    flip = if spec.mirror, do: fn {x, y} -> {@width - x, y} end, else: & &1
    targets = Map.get(spec, :targets, [])

    seg = fn part, from, to, muscle ->
      %{
        w: Map.fetch!(@thick, part),
        muscle: muscle,
        targeted: muscle in targets,
        d:
          Enum.map(frames, fn f ->
            polyline([flip.(Map.fetch!(f, from)), flip.(Map.fetch!(f, to))])
          end)
      }
    end

    dot = fn key, r ->
      %{
        r: r,
        cx: Enum.map(frames, fn f -> f |> Map.fetch!(key) |> flip.() |> elem(0) |> fmt() end),
        cy: Enum.map(frames, fn f -> f |> Map.fetch!(key) |> elem(1) |> fmt() end)
      }
    end

    leg = fn which, tone, edge ->
      [hip, knee, foot, toe] =
        Enum.map(~w(hip knee foot toe), &String.to_existing_atom("#{&1}_#{which}"))

      thigh_active = :quads in targets or :hamstrings in targets
      shin_active = :calves in targets

      %{
        name: String.to_existing_atom("leg_#{which}"),
        tone: tone,
        edge: edge,
        parts: [
          Map.put(seg.(:thigh, hip, knee, :quads), :targeted, thigh_active),
          Map.put(seg.(:shin, knee, foot, :calves), :targeted, shin_active),
          seg.(:foot, foot, toe, :feet)
        ],
        shapes: [],
        under: [],
        over: []
      }
    end

    arm = fn which, tone, edge ->
      [shoulder, elbow, hand] =
        Enum.map(~w(sh elbow hand), &String.to_existing_atom("#{&1}_#{which}"))

      upper_active = :triceps in targets or :biceps in targets or :deltoids in targets
      forearm_active = :forearms in targets
      hand_active = forearm_active

      %{
        name: String.to_existing_atom("arm_#{which}"),
        tone: tone,
        edge: edge,
        parts: [
          Map.put(seg.(:upper_arm, shoulder, elbow, :triceps), :targeted, upper_active),
          Map.put(seg.(:forearm, elbow, hand, :forearms), :targeted, forearm_active)
        ],
        shapes: [],
        under: [Map.merge(dot.(hand, @hand_r), %{muscle: :forearms, targeted: hand_active})],
        over: []
      }
    end

    trunk =
      case spec.view do
        :side ->
          belly_active = :core in targets or :glutes in targets
          chest_active = :chest in targets or :back in targets

          %{
            name: :trunk,
            tone: :body,
            edge: false,
            parts: [
              seg.(:neck, :neck, :nape, :neck),
              Map.put(seg.(:belly, :pelvis, :chest, :core), :targeted, belly_active),
              Map.put(seg.(:chest, :chest, :collar, :chest), :targeted, chest_active)
            ],
            shapes: [],
            under: [],
            over: [
              Map.merge(dot.(:head, @head_r), %{
                visor:
                  Enum.map(frames, fn f ->
                    {hx, hy} = flip.(f.head)
                    sign = if spec.mirror, do: -1.0, else: 1.0
                    polyline([{hx + sign * 1.0, hy - 1.2}, {hx + sign * (@head_r - 0.6), hy}])
                  end)
              })
            ]
          }

        # Seen from the front the trunk is the shape between the shoulders and
        # the hips, not a line down the spine.
        :front ->
          torso_active = :chest in targets or :back in targets or :core in targets

          %{
            name: :trunk,
            tone: :body,
            edge: false,
            parts: [seg.(:neck, :neck, :nape, :neck)],
            shapes: [
              %{
                w: @thick.trunk_edge,
                muscle: :chest,
                targeted: torso_active,
                d:
                  Enum.map(frames, fn f ->
                    polyline(Enum.map([f.sh_a, f.sh_b, f.hip_b, f.hip_a], flip)) <> "Z"
                  end)
              }
            ],
            under: [],
            over: [
              Map.merge(dot.(:head, @head_r), %{
                visor:
                  Enum.map(frames, fn f ->
                    {hx, hy} = flip.(f.head)
                    polyline([{hx - 2.8, hy - 0.8}, {hx + 2.8, hy - 0.8}])
                  end)
              })
            ]
          }
      end

    {back, top} =
      case spec.view do
        :side ->
          {[leg.("b", :far, false), arm.("b", :far, false), trunk, leg.("a", :near, true)],
           [arm.("a", :near, true)]}

        :front ->
          {[leg.("a", :near, true), leg.("b", :near, true), trunk],
           [arm.("a", :near, true), arm.("b", :near, true)]}
      end

    {stops, _} =
      Enum.map_reduce(keys, 0.0, fn pose, at ->
        {%{name: pose.name, at: Float.round(at, 2)}, at + pose.hold + pose.move}
      end)

    %{
      view: spec.view,
      seconds: Float.round(seconds, 2),
      frames: length(frames),
      stops: stops,
      floor: spec.floor,
      ground: @ground,
      box: frame_box(frames, spec.props, flip),
      back: back,
      top: top,
      props: Enum.map(spec.props, &bake_prop(&1, frames, flip)),
      targets: targets
    }
  end

  # The part of the stage the figure uses, with room round it: wide enough
  # that a standing figure is not a sliver, and always down to the floor.
  defp frame_box(frames, props, flip) do
    points =
      for frame <- frames,
          {key, {_, _} = point} <- frame,
          key not in [:head],
          do: flip.(point)

    heads =
      for frame <- frames,
          {x, y} = flip.(frame.head),
          dx <- [-@head_r, @head_r],
          do: {x + dx, y - @head_r}

    held = if Enum.any?(props, &Map.has_key?(&1, :hold)), do: 10.0, else: 0.0

    # Equipment the figure uses is in the picture too.
    gear =
      Enum.flat_map(props, fn
        %{kind: :block} = b -> [flip.({b.x, b.y}), flip.({b.x + b.w, b.y + b.h})]
        %{kind: :box} = b -> [flip.({b.x, @ground - b.h}), flip.({b.x + b.w, @ground})]
        %{kind: :disc, at: {x, y}, r: r} -> [flip.({x - r, y - r}), flip.({x + r, y + r})]
        %{kind: :dome} = d -> [flip.({d.x - d.w / 2, @rest - d.h}), flip.({d.x + d.w / 2, @rest})]
        %{kind: :line} = l -> for {_, _} = fixed <- [l.from, l.to], do: flip.(fixed)
        _ -> []
      end)

    points = points ++ gear

    {xs, ys} = Enum.unzip(points ++ heads)
    left = Enum.min(xs) - 13 - held
    right = Enum.max(xs) + 13 + held
    top = Enum.min(ys) - 10 - held

    width = max(right - left, 96.0)
    left = max(min(left - (width - (right - left)) / 2, @width - width), 0.0)
    top = max(min(top, @floor - 52), 0.0)

    %{x: fmt(left), y: fmt(top), w: fmt(min(width, @width)), h: fmt(@height - top)}
  end

  defp bake_prop(%{kind: :mat} = mat, _frames, flip) do
    {x1, _} = flip.({mat.from, 0.0})
    {x2, _} = flip.({mat.to, 0.0})
    %{kind: :mat, x: fmt(min(x1, x2)), y: fmt(@ground), w: fmt(abs(x2 - x1)), h: "1.8"}
  end

  defp bake_prop(%{kind: :box} = box, _frames, flip) do
    {x1, _} = flip.({box.x, 0.0})
    {x2, _} = flip.({box.x + box.w, 0.0})
    %{kind: :box, x: fmt(min(x1, x2)), y: fmt(@ground - box.h), w: fmt(box.w), h: fmt(box.h)}
  end

  defp bake_prop(%{kind: :block} = block, _frames, flip) do
    {x1, _} = flip.({block.x, 0.0})
    {x2, _} = flip.({block.x + block.w, 0.0})
    %{kind: :block, x: fmt(min(x1, x2)), y: fmt(block.y), w: fmt(block.w), h: fmt(block.h)}
  end

  defp bake_prop(%{kind: :disc, at: at, r: r}, _frames, flip) do
    {x, y} = flip.(at)
    %{kind: :disc, cx: fmt(x), cy: fmt(y), r: fmt(r)}
  end

  defp bake_prop(%{kind: :dome} = dome, _frames, flip) do
    {x, _} = flip.({dome.x, 0.0})
    half = dome.w / 2

    %{
      kind: :dome,
      d:
        "M#{fmt(x - half)} #{fmt(@ground)}A#{fmt(half)} #{fmt(dome.h + @ground - @rest)} 0 0 1 #{fmt(x + half)} #{fmt(@ground)}Z"
    }
  end

  # A line follows whichever of its ends is a hand or a foot.
  defp bake_prop(%{kind: :line} = line, frames, flip) do
    place = fn
      {_, _} = fixed, _frame -> fixed
      :hands, frame -> mid(frame.hand_a, frame.hand_b)
      limb, frame -> Map.fetch!(frame, limb)
    end

    %{
      kind: :line,
      style: line.style,
      moves: is_atom(line.from) or is_atom(line.to),
      d:
        Enum.map(frames, fn frame ->
          polyline([flip.(place.(line.from, frame)), flip.(place.(line.to, frame))])
        end)
    }
  end

  # Something held: where it is gripped, and where its weight sits, which is
  # below the grip, beyond it along the forearm, or above it.
  defp bake_prop(prop, frames, flip) do
    places =
      Enum.map(frames, fn frame ->
        {grip, weight} = grip_and_weight(prop, frame)
        {flip.(grip), flip.(weight)}
      end)

    %{
      kind: prop.kind,
      r: %{kettlebell: 4.4, dumbbell: 2.6, ball: 4.8, bar: 3.2}[prop.kind],
      # Behind the body when a pose says so; otherwise what the far hand
      # holds alone is behind, and anything else in front.
      behind:
        Enum.map(frames, fn frame ->
          case frame.weight do
            :behind -> true
            :front -> false
            nil -> prop.hold == :hand_b
          end
        end),
      cx: Enum.map(places, fn {_grip, {x, _y}} -> fmt(x) end),
      cy: Enum.map(places, fn {_grip, {_x, y}} -> fmt(y) end),
      handle: Enum.map(places, fn {grip, weight} -> polyline([grip, weight]) end)
    }
  end

  defp grip_and_weight(prop, frame) do
    {grip, elbow} =
      case prop.hold do
        :hand_a -> {frame.hand_a, frame.elbow_a}
        :hand_b -> {frame.hand_b, frame.elbow_b}
        :hands -> {mid(frame.hand_a, frame.hand_b), mid(frame.elbow_a, frame.elbow_b)}
      end

    drop = if prop.kind == :kettlebell, do: 5.0, else: 0.0

    weight =
      case prop.mode do
        :hang -> add(grip, {0.0, drop})
        :up -> add(grip, {0.0, -drop})
        :arm -> add(grip, mul(unit(sub(grip, elbow)), drop))
      end

    {grip, weight}
  end

  defp polyline([first | rest]) do
    "M" <> xy(first) <> Enum.map_join(rest, "", &("L" <> xy(&1)))
  end

  defp xy({x, y}), do: fmt(x) <> " " <> fmt(y)
  defp fmt(value), do: :erlang.float_to_binary(value * 1.0, decimals: 1)

  # ── Plane geometry ───────────────────────────────────────────────────

  # A direction: 0 is straight up, turning toward the way the figure faces.
  defp dir(degrees) do
    radians = degrees * :math.pi() / 180
    {:math.sin(radians), -:math.cos(radians)}
  end

  defp add({ax, ay}, {bx, by}), do: {ax + bx, ay + by}
  defp sub({ax, ay}, {bx, by}), do: {ax - bx, ay - by}
  defp mul({x, y}, k), do: {x * k, y * k}
  defp dot({ax, ay}, {bx, by}), do: ax * bx + ay * by
  defp len({x, y}), do: :math.sqrt(x * x + y * y)
  defp mid(a, b), do: mul(add(a, b), 0.5)

  defp unit(vector) do
    case len(vector) do
      length when length < 1.0e-6 -> {0.0, 1.0}
      length -> mul(vector, 1 / length)
    end
  end
end
