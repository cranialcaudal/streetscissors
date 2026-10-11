# Exercise figures: handoff to another agent

Written 2026-10-10 for an agent that has never seen this project (Gemini Flash in
Google Antigravity, or anyone). Read all of it before running anything. It is a procedure
to follow, not background to skim.

## What you are working on

The exercise wiki (`/fitness/wiki/<slug>`) shows, for each of 113 exercises, a short looping
film of a 3D figure doing the exercise. Each film is rendered from a small pose file. Your
job is to make the figures correct, one at a time, by editing pose files and re-rendering.

You are **not** redesigning the body, the renderer, or the website.

Three things about the film are worked out for you. Do not try to set them in a pose file,
and do not edit the code that does them:

- **Which muscles are lit, and how strongly.** Three strengths. Full: the muscles the
  exercise's page names (**primary**). Half: the links that steady the load, such as the grip
  under a weight and the trunk between the hands and the floor (**chain**). Faint: the rest of
  the body holding still, such as the legs under a standing lift (**brace**). The page gives
  the first; rules read the other two off the figure (`lib/web/fitness/chain.ex`): where the
  load is, and what the body rests on.
- **Hands, wrists, shoulders and feet.** A hand has no fingers: it is a palm and a plate of
  fingers hinged at the knuckles, on a wrist that bends. What it does is read off what is
  beside it. Round a bar, a handle or a band's end it is a fist. On a floor, a box or a wall
  it lies flat with the wrist bent back under the forearm. On a ball, a dome or a bell the
  fingers fold over the curve. With nothing near it, it is a loose fist that hangs a little
  from the wrist when the arm is held level. The shoulder rises with an arm reaching overhead
  and comes forward with one reaching out. A foot up on its toes bends where the toes begin.
  **The only way you change a hand is by where you put it**: a hand "on the floor" at y = 95
  is four units above the floor, so it is drawn as a fist hovering in the air. Put it at
  y = 99 (or on the top of the box, or on the bar) and the hand changes by itself.
- **The kettlebell** has a handle. Put the hand where the handle should be; the bell hangs
  from it.

## Rules you must not break

1. **Never deploy, restart or stop anything.** Do not run `./redeploy.sh`, `./rollback.sh`,
   `systemctl`, `mix phx.server` or `iex -S mix phx.server`. This machine is the live server.
2. **One render at a time.** Never start a second `mix fitness.film` while one is running, and
   never run it in parallel. Two renders at once produce blank pictures silently.
3. **Do not add a key to a pose file that this document does not list.** The live site refuses
   a pose file with a key it does not know and the page then shows no figure at all.
4. **Do not use the keys `stance` or `grip` in `content/fitness/figures/`** until the owner says
   the site has been deployed. They are in the engine but not yet on the live site. (`grip` is
   already live and in six files: leave those as they are; add it nowhere new without asking.)
5. **Do not delete files.** Do not edit anything outside the paths in "Files you may edit".
6. **Do not commit or push** unless the owner asks. The pose files are not in git at all.
7. **Never say a figure is right because it validates.** A file that passes every check can
   still be a picture of the wrong exercise. You must open the still images and look.
8. If a command fails twice, stop and write down what happened. Do not improvise around it.

## Files

| Path | What it is | May you edit it? |
|---|---|---|
| `content/fitness/figures/<slug>.json` | The pose file for one exercise | **Yes** |
| `content/fitness/exercise-wiki/<group>/<slug>.md` | The exercise's page. Read "Goal" and "Execution" | No |
| `tmp/figure-refs/photos/<slug>-0.jpg`, `-1.jpg` | Reference photographs, start and end, for 47 exercises (`tmp/figure-refs/map.json` lists which) | No |
| `tmp/figure-audit.md` | An earlier audit's notes per figure. Leads, not facts | No |
| `lib/web/fitness/figure.ex` | The pose engine. Its `@moduledoc` documents every pose key | No (read it) |
| `priv/figure/figure3d.js` | The 3D body and renderer | No |
| `priv/figure/check.mjs` | The rule checker | No |
| `lib/web/fitness/chain.ex` | The rules for which muscles are lit at half and faint strength | No |

All commands are run from the repository root, `~/streetscissors`.

## The pose file, in one screen

The stage is 160 wide. The floor is y = 100 and **y grows downward**. A standing figure is
about 80 tall. A foot or hand resting on the floor is at y = 99. A body lying down has its
pelvis at y = 95. The figure faces right (+x).

```json
{
  "view": "side",
  "planted": ["foot_a", "foot_b"],
  "props": [{"kind": "mat", "from": 30, "to": 130},
            {"kind": "kettlebell", "hold": "hands", "mode": "hang"}],
  "poses": [
    {"name": "stand", "hold": 0.3, "move": 1.2, "pelvis": [80, 60], "lean": 0,
     "feet": [80, 99], "hands": [86, 42], "elbows": "down", "knees": "front"},
    {"name": "bottom", "hold": 0.4, "move": 1.2, "pelvis": [70, 82], "lean": 25,
     "feet": [80, 99], "hands": [84, 62], "elbows": "down", "knees": "front"}
  ]
}
```

- `pelvis` `[x, y]`: the hip joint. `lean`: the back's angle from upright in degrees,
  positive toward the facing side (90 = face down, -90 = on the back). `curl`: rounding of
  the upper back. `head`: the neck. `turn`: shoulders turned about the spine.
- Where a hand or foot **is**: `hand_a`, `hand_b`, `foot_a`, `foot_b` as `[x, y]`, or `hands`
  / `feet` for both. `a` is the near limb. Elbows and knees are worked out for you.
- Or where a limb **points**: `arm_a`, `arm_b`, `leg_a`, `leg_b` (or `arms`, `legs`) as
  `[angle, reach]`: angle from straight up turning toward the facing side (90 = forward,
  180 = down), reach from 0 to 1.
- `elbows` / `knees` (or `elbow_a` …): which way the joint bends: `up`, `down`, `front`,
  `back`, `headward`, `feetward`. **If the same joint bends different ways in two poses the
  file is refused**; give the same word in every pose.
- `side` (-1 to 1), `spread` (stage units, hands apart), `flare` (0 to 1, elbows out): depth
  cues. `spread` must be in every pose of a file or in none.
- Props: `mat`, `box` / `block` (`x`, `y`, `w`, `h`), `disc` (`at`, `r`: a bar seen end-on),
  `dome`, `line` (`from`, `to`, `style`: `band` or `pole`, optional `depth`), and held weights
  `kettlebell`, `dumbbell`, `bar`, `ball` with `hold` (`hands`, `hand_a`, `hand_b`) and `mode`
  (`hang` = below the hand, `arm` = in line with the forearm, `up` = above the hand).
- `name`, `hold` (seconds in the pose), `move` (seconds to reach the next pose).

The full list is the `@moduledoc` of `lib/web/fitness/figure.ex`. If a key is not there and
not here, it does not exist.

## The four commands

```bash
# 1. The rules. Fast (2 seconds for everything), draws nothing. Also reports a file the
#    pose engine refuses, and why.
mix fitness.film --check <slug>

# 2. A picture of every pose, to look at. About 10 seconds. Writes <slug>-0.png, -1.png …
timeout -k 5 150 mix fitness.film --stills /tmp/figure-stills <slug> < /dev/null

# 3. The film, onto the live site. About 60 seconds. Must print "1 filmed".
UPLOADS_PATH=$HOME/streetscissors-data/uploads timeout -k 5 300 mix fitness.film --all <slug> < /dev/null
```

```bash
# 4. Which muscles the film will light, in three strengths. Instant.
mix fitness.film --tiers <slug>
```

Always keep the `timeout` and the `< /dev/null`. A render can hang, and inside a loop the
command will otherwise swallow the rest of your list. If command 2 prints nothing and writes
no file, the pose file is invalid: run command 1 to see why.

## The algorithm, for one figure

Do these steps in order. Do not skip a step. Do not batch several figures into one step.

1. **Read** the page's "Goal" and "Execution". Write one sentence: the body position at the
   start, at the end, and what is held.
2. **Look** at `tmp/figure-refs/photos/<slug>-0.jpg` and `-1.jpg` if they exist. They show the
   real start and end. (A few are a near relative of the exercise, not the same one: the
   page's text wins over the photograph.)
3. **Check**: `mix fitness.film --check <slug>`. Note every line it prints.
4. **Draw** the stills (command 2) and open every image. For each pose answer, in writing:
   - Is the posture what the page says (standing, seated, lying, which way up)?
   - Are the hands on what they should hold, and the feet on the floor or the box? A hand
     meant to rest on something must be drawn flat on it (or wrapped over it, if it is
     round), and a hand meant to hold a bar must be a fist round it. A loose fist near a
     surface or a bar means the pose has the hand a few units off: move the hand, not
     anything else.
   - Is the equipment there, in the right place, and not through the body?
   - Does the pose match the reference photograph?
   - Are the lit muscles sensible? Run command 4. Strongest orange should be on the muscles
     the page names, paler on the grip and trunk carrying the load, faintest on what only
     holds the body up. If a tier looks wrong (for example legs lit on a seated exercise),
     **write it in your log and change nothing**: the fix is in the rules, not the pose file,
     and the rules are not yours to edit. One exception: if the tiers are wrong because the
     *pose* is wrong (a figure meant to be seated whose hips float above its bench, a hand
     meant to be on the floor that hovers above it), fix the pose.
5. If steps 3 and 4 found **nothing wrong**: go to step 9.
6. **Change one thing** in the pose file: the smallest edit that fixes the worst problem.
   Typical edits: move `hands`, move `pelvis`, change `lean`, move a prop. Keep `planted`
   limbs in the same place in every pose.
7. **Check again** (command 1). If the engine refuses the file, read its message; it names
   the pose and the limb. "out of reach" means move the hand or foot closer to the body, or
   the pelvis toward it. "bends one way in … and the other in …" means give that joint the
   same direction word in every pose.
8. **Draw again** and look (step 4). Repeat steps 6 to 8 **at most three times**. If the
   figure is still wrong after three, undo your edits to that file, record it as "could not
   fix" with the reason, and move to the next figure.
9. **Film** it (command 3) and confirm it printed `1 filmed`.
10. **Record** one line in your log: slug, what was wrong, what you changed, result.

Keep a copy of every pose file before your first edit to it, in a folder of your own, so
step 8's "undo" is a copy back.

## What "right" means

- The rule check prints nothing for the figure, **or** only prints something listed under
  "Known limits" below.
- Every pose image shows the exercise the page describes.
- Start and end poses differ visibly in the way the movement goes.
- Nothing is cut off by the edge of the picture.

## Known limits: do not try to fix these with pose edits

- **Hex-bar figures** (`hexbar-carries`, `hexbar-jumps`, `hexbar-rdl`, `hex-flat-side-deadlift`)
  and `farmers-walk`: there is no hex-bar prop, so the bar is drawn through the hips. Leave.
- **An arm that wraps across the body** (`kb-russian-twist`, `kb-side-plank-reach`): drawn
  straight through the trunk. The check will go on flagging it. Leave.
- **No such prop**: a jump rope, a speed ladder, a kickboard, a parachute canopy, a rope or
  bar on a cable. Do not fake them with other props.
- **Lying on the side** (`sleeper-stretch`): the engine cannot pose it.
- Swimming figures are drawn from above with no floor. The check skips most rules for them.

Record these as "known limit" and move on.

## The work, in order

**Task 1. Re-film everything with the current look.** On 2026-10-10 the body's outline, the
kettlebell, the hands, feet and shoulders and the three strengths of lit muscle all changed,
and nearly every film predates them. One at a time:

```bash
for f in content/fitness/figures/*.json; do
  s=$(basename "$f" .json)
  out=$(UPLOADS_PATH=$HOME/streetscissors-data/uploads timeout -k 5 300 mix fitness.film --all "$s" < /dev/null 2>&1 | tail -1)
  echo "$s: $out"
done
```

About 100 minutes. Every line must end `1 filmed, 0 already current, 0 not filmed.` Re-run
any slug that did not. Do nothing else on the machine's graphics card meanwhile.

**Task 2. The figures the rule check still flags.** Run `mix fitness.film --check` with no
slug. Apply the algorithm to each figure it lists that is not a known limit. Expected:
`zercher-hold`, `kb-halos`, `medicine-ball-rotational-throws`, `hip-thrusts`,
`couch-stretch`, `decline-leg-raises`, `lat-smashes`, `thoracic-roller-extension`.

**Task 2b. A pass over the lit muscles.** Run command 4 for every slug and read the three
lists against the exercise. You are looking for the rules guessing the body's situation
wrong: a seated exercise treated as standing (legs in `brace`), an exercise with a band that
shows no `chain`, a hanging exercise with no `forearms`. Do not fix anything. Make a table:
slug, what the tiers say, what looks wrong and why. That table is the most useful thing you
can hand back, because it is how the rules get better.

**Task 3. The audit's leftovers.** `push-up-plus` (elbows should stay straight; only the
upper back rounds), `banded-ankle-dorsiflexion` (the front knee should travel forward over the
toes), `sub-maximal-holds` (hands should grip the edge, not pass through the slab),
`tricep-pushdowns`, `incline-dumbbell-press` (the bench back should lie under the torso).

**Task 4. The gym and kettlebell exercises against their photographs.** For each slug in
`tmp/figure-refs/map.json`, apply the algorithm. Start with the kettlebell circuit:
`goblet-squats`, `kb-swings`, `kb-single-arm-row`, `kb-russian-twist`, `kb-pullover`,
`kb-half-kneeling-press`, `kb-lunges`, `kb-halos`, `kb-side-plank-reach`, `plank`, `push-ups`,
`single-leg-calf-raises`, `hollow-hold`, `y-t-w-raises`.

Stop after any task if you are unsure, and report.

## When you finish, or stop

Write a report with: the figures you changed and what you changed in each; the figures you
could not fix and why; the last output of `mix fitness.film --check`; the table from Task 2b;
and anything in this document that turned out to be wrong.
