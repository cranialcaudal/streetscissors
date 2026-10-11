defmodule Web.Fitness.Chain do
  @moduledoc """
  The kinetic chain: which muscles hold an exercise together besides the ones
  its page names.

  A page's `anatomy:` says what an exercise is *for*: a curl is for the biceps.
  But a load in the hand does not reach the floor through the biceps alone. It
  goes through the grip, the shoulder, the trunk and whatever the body stands
  on, and every link on that path works to keep it there. This module reads
  the path off the figure itself (where the load is, what the body rests on)
  and names the links in three tiers, which the film lights at three strengths:

    * **primary**: the page's own muscles (`Web.Fitness.Clip.muscles/1`), and
      the finer groups `detail/1` hears in the same text;
    * **chain**: the links next to the load, which steady it: the grip under
      anything held, the trunk between a load in the hands and feet on the
      floor, the shoulder blades under a load overhead;
    * **brace**: the rest of the way to the floor, which only has to stay
      stiff: the legs under a standing lift, the hips and thighs in a plank.

  The rules are few and geometric on purpose. They cannot know an exercise;
  they know that a hand on the floor carries weight and a foot off it does not.
  A muscle already in a stronger tier is left out of a weaker one.

  None of this enters `Web.Fitness.Clip.source/2`: the film's hash is still the
  figure and the page's own muscles, so the live site and the bench agree on
  which film belongs to which figure whatever these rules become.
  """

  @floor 100.0

  # Finer groups than the page's seventeen, heard in the same `anatomy:` text.
  @detail [
    {~r/rhomboid|mid[- ]?trap|scapular retract/i, "rhomboids"},
    {~r/hip flexor|iliopsoas|psoas/i, "hipflexors"},
    {~r/abductor|glute(us)? med|hip stabili[sz]/i, "abductors"},
    {~r/tibialis|shin|dorsiflex/i, "tibialis"}
  ]

  @doc "The finer muscle groups a page's `anatomy:` names, beside its seventeen."
  def detail(anatomy) when is_binary(anatomy),
    do: for({said, muscle} <- @detail, Regex.match?(said, anatomy), do: muscle)

  def detail(_anatomy), do: []

  @doc """
  The three tiers for a figure: `raw` is its file as decoded, `track` what
  `Web.Fitness.Figure.track/2` made of it, `primary` the page's muscles.
  `%{primary: [...], chain: [...], brace: [...]}`.
  """
  def tiers(raw, track, primary) do
    facts = facts(raw, track)

    chain =
      []
      |> add(facts.loaded, ~w(forearms))
      |> add((facts.standing or facts.seated) and facts.loaded, ~w(abs obliques lowback))
      |> add(facts.overhead, ~w(traps serratus))
      |> add(facts.hanging, ~w(forearms abs))
      |> add(facts.hands_down, ~w(serratus delts abs obliques))
      |> add(facts.single_leg, ~w(abductors calves obliques))
      |> add(facts.hinge, ~w(lowback hamstrings glutes rhomboids))

    brace =
      []
      |> add(facts.standing and facts.loaded, ~w(glutes quads calves))
      |> add(facts.hands_down, ~w(glutes quads))
      |> add(facts.hanging, ~w(obliques lats))

    chain = Enum.uniq(chain) -- primary
    %{primary: primary, chain: chain, brace: (Enum.uniq(brace) -- primary) -- chain}
  end

  @doc """
  What the rules go by, read off the figure: `standing` on its feet, `loaded`
  in the hands (a weight, or a band or cable), the load `overhead`, `hanging`
  from its hands, `hands_down` bearing weight, `seated`, on a `single_leg`, in a
  `hinge`.
  """
  def facts(raw, track) do
    frames = track.frames
    count = max(length(frames), 1)
    share = fn test -> Enum.count(frames, test) / count end
    down? = fn [_x, y] -> y >= @floor - 3.5 end
    floor? = track.floor == true
    side? = to_string(track.view) == "side"

    feet_down = share.(fn f -> down?.(f.foot_a) or down?.(f.foot_b) end) > 0.5
    hands_down = floor? and share.(fn f -> down?.(f.hand_a) or down?.(f.hand_b) end) > 0.5
    upright = Enum.all?(frames, fn f -> Enum.at(f.pelvis, 1) < 88 end)
    # sat on something: the thighs lie level the whole way through, which a
    # squat's only do at the bottom
    level? = fn f, knee -> abs(Enum.at(f.pelvis, 1) - Enum.at(Map.fetch!(f, knee), 1)) < 7 end
    seated = Enum.all?(frames, &(level?.(&1, :knee_a) and level?.(&1, :knee_b)))
    standing = floor? and feet_down and upright and not hands_down and not seated
    props = List.wrap(raw["props"])

    loaded =
      Enum.any?(props, fn prop ->
        prop["kind"] in ~w(kettlebell dumbbell bar ball) or
          (prop["kind"] == "line" and
             Enum.any?([prop["from"], prop["to"]], &(&1 in ~w(hands hand_a hand_b))))
      end)

    above_head = fn f ->
      min(Enum.at(f.hand_a, 1), Enum.at(f.hand_b, 1)) < Enum.at(f.head, 1) - 2
    end

    lean =
      raw |> Map.get("poses", []) |> Enum.map(&abs(&1["lean"] || 0)) |> Enum.max(fn -> 0 end)

    %{
      standing: standing,
      loaded: loaded,
      overhead: loaded and (standing or (floor? and seated)) and share.(above_head) > 0.2,
      hanging: not floor? and side? and share.(above_head) > 0.4,
      hands_down: hands_down,
      seated: floor? and seated and upright,
      single_leg: standing and share.(fn f -> down?.(f.foot_a) != down?.(f.foot_b) end) > 0.5,
      hinge: standing and loaded and lean >= 40
    }
  end

  defp add(list, true, muscles), do: list ++ muscles
  defp add(list, _false, _muscles), do: list
end
