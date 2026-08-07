# Weekly Regimen → Google Calendar

This is a calendar-building reference generated from the current [weekly regimen](/fitness/regimen) and [master plan](/fitness/regimen) (2026-07-20 redesign). It's a snapshot, not a live sync — if the regimen changes later, this page won't update itself. Re-generate it if things drift.

**How to use it:** for each fixed event below, create it once in Google Calendar and set the matching recurrence. For the variable ones (Friday, Saturday, Sunday, and the Tue/Thu evening slot), you'll need slightly different handling — see the notes under each.

---

## Fixed weekly events (same time, every week)

| Day | Event | Time | Location | Recurrence |
|---|---|---|---|---|
| Monday | No Focus – Full Body | 5:40–7:00 AM | UC Davis ARC | Weekly |
| Monday | Ironman Swim (easy, 90 min) | 7:05–8:35 AM | Rec Pool (across the street from the ARC) | Weekly |
| Monday | Pickleball | Evening, time TBD | — | Weekly |
| Tuesday | Bike Commute In (TCR C2) | 6:10–7:10 AM | Sacramento → UC Davis ARC | Weekly |
| Tuesday | Upper Body Gym | 7:10–8:30 AM | UC Davis ARC | Weekly |
| Tuesday | Bike Commute Home | ~5:30–6:30 PM | UC Davis → Sacramento | Weekly |
| Wednesday | ADRC Ride (City Escape) | Sometime during the day, flexible | Sacramento → ADRC | Weekly |
| Wednesday | Long Run (5–10 km, growing) | Evening | Sacramento | Weekly |
| Thursday | Bike Commute In (TCR C2) | 6:10–7:10 AM | Sacramento → UC Davis ARC | Weekly |
| Thursday | Lower Body Gym | 7:10–8:30 AM | UC Davis ARC | Weekly |
| Thursday | Bike Commute Home | ~5:30–6:30 PM | UC Davis → Sacramento | Weekly |

Monday leaves the house by **5:10 AM** (drive, not the bike — the ARC first, then a short walk across the street to the Rec Pool). Tuesday and Thursday leave by **6:10 AM** (bike commute straight to the ARC).

---

## Variable events (check the actual week before you commit a time)

### Tuesday / Thursday evening
Pickleball by default. On a week with a weekday-league game, the game replaces pickleball that evening instead — the game calendar decides which, not a fixed schedule, so this one isn't safe to pre-set as a single recurring event. Easiest approach: keep a recurring **"Pickleball (check for game)"** placeholder on both evenings, and manually swap the title/time on weeks there's a game.

### Friday — office or remote?
Whether a given Friday is an office day isn't on a strict fixed cadence, so don't pre-set this as alternating weeks. Instead, each week check whether it's an office Friday, then add:

| If office Friday | Time | Location |
|---|---|---|
| Bike Commute In | 8:00–9:00 AM | Sacramento → Davis |
| Survival & Speed Swim (2 hr) | ~12:00–2:00 PM | Rec Pool |
| Bike Commute Home | ~5:30–6:30 PM | Davis → Sacramento |

| If remote Friday | Time | Location |
|---|---|---|
| Fartlek Run | Flexible, time TBD | Sacramento |

### Sunday — which game time?
Sunday-league games land on **8:00 AM, 11:00 AM, or 2:00 PM**, varying by week — check the league schedule first, then add that week's actual slot:

| Game time | Pre-Game Warmup | Game |
|---|---|---|
| 8:00 AM | 7:00–8:00 AM | 8:00 AM (duration varies) |
| 11:00 AM | 10:00–11:00 AM | 11:00 AM (duration varies) |
| 2:00 PM | 1:00–2:00 PM | 2:00 PM (duration varies) |

Tennis with your girlfriend can go before or after — your call each week, just keep the warmup non-negotiable either way.

---

## Saturday — 4-week rotating cycle

This one actually **is** a fixed pattern Google Calendar can handle natively, just not a simple "every week." Set up four separate recurring events, each repeating **every 4 weeks**, staggered one week apart:

| Week | Event | Time | Location |
|---|---|---|---|
| 1 | Big Hike (solo) | Morning, flexible | Bike out to Folsom/Auburn |
| 2 | DOCO + Hike | Morning | DOCO 24 Hour Fitness |
| 3 | Ironman Brick (Folsom) | Morning | RT (light rail) to Folsom Lake |
| 4 | DOCO + Hike | Morning | DOCO 24 Hour Fitness |

**Setup steps:**
1. Figure out which of the four this coming Saturday actually is.
2. Create that event on this Saturday. Under recurrence, choose **Custom** → "Weekly, every **4** weeks, on Sat" (not "every week" or "every 2 weeks" — the interval has to be 4).
3. The following Saturday, create *next* week's type the same way — also custom, every 4 weeks, starting from that date.
4. Repeat for weeks 3 and 4. You'll end up with four independent recurring series, each firing once a month, landing on consecutive Saturdays in rotation.

---

## Fixed-time recap for quick entry

If you'd rather just batch-enter the unambiguous ones first and handle the four variable days separately:

```
Mon 5:40–7:00 AM   No Focus – Full Body        UC Davis ARC       weekly
Mon 7:05–8:35 AM   Ironman Swim                 Rec Pool           weekly
Tue 6:10–7:10 AM   Bike Commute In              → UC Davis ARC     weekly
Tue 7:10–8:30 AM   Upper Body Gym                UC Davis ARC       weekly
Wed (evening)      Long Run (5–10 km)            Sacramento         weekly
Thu 6:10–7:10 AM   Bike Commute In               → UC Davis ARC     weekly
Thu 7:10–8:30 AM   Lower Body Gym                UC Davis ARC       weekly
```
