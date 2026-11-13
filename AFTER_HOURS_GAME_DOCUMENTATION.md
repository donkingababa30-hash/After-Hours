# AFTER HOURS — Game Design & Mechanics Documentation

A 2D top-down psychological horror game. You are the night-shift security guard at
Riverview Mall. Three nights. Escalating darkness. Something is in the building
with you.

Engine: Godot 4.7 (GDScript, GL Compatibility renderer).
Internal resolution: 640x360, upscaled to a 1280x720 window with nearest-neighbour
filtering (pixel-art look).

---

## 1. THE PITCH

Riverview Mall closed its doors for the last time six years ago, but somebody still
pays for a night shift. You walk the rounds, you file the reports, you keep the
lights on. The building does not want you to finish your shift.

The horror is mundane first and paranormal second: the job itself is the trap.
Every duty has a deadline. Every report you ignore is logged against you. The mall
is a workplace that turns hostile, and the scariest thing in it is that you are
expected to keep working anyway.

Touchstones: FAITH (minimal, readable, unsettling), Lone Survivor (resource
scarcity, nerve), Yuppie Psycho (dark-comic workplace dread), FNAF: Into the Pit
(shift structure, listening and watching as the core verb).

---

## 2. STRUCTURE OF PLAY

The game is three nights. Each night starts at 10:00 PM and runs to a fixed end
minute, ticking at a night-specific rate.

| Night | Title       | Ends | Tick rate | Hunter gap | Duty deadline | Threat cap | Warden |
|-------|-------------|------|-----------|------------|---------------|------------|--------|
| 1     | PROBATION   | 240' | 2.0 s/min | 150 s      | 110 min       | 1          | no     |
| 2     | THE ROUNDS  | 300' | 1.8 s/min | 70 s       | 65 min        | 2          | no     |
| 3     | THE WARDEN  | 360' | 1.7 s/min | 45 s       | 55 min        | 3          | yes    |

A night is survived by reaching its end minute alive. Survive all three and the
ending plays. Die, or let three rounds expire, and the run ends at the game over
screen. Progress (best night reached, total evidence) is kept between runs.

The clock is always visible. The current objective is always on the board. The
guard is never allowed to be idle without the game telling them so.

---

## 3. THE CORE LOOP

1. The duty board hands you a round: a repair, a reset, a fetch, or an anomaly to
   log. It names a room and a deadline.
2. You walk there. Walking is dangerous — hunters path around the mall using A*,
   and the mall gets darker every hour.
3. You complete the round (press E, sometimes a small hands-on minigame).
4. The board clears an item and hands you the next one.
5. When the list runs out, the night does not go quiet — the finale starts and the
   mall comes hunting. From that point the **Night Watch** takes over: the mall
   keeps handing you incidents to walk, each with its own clock.
6. Miss three rounds, of any kind, and management pulls you off the shift.

The tension is scheduling. You are always deciding whether to keep working or
whether the thing you can hear is close enough to matter yet.

---

## 4. CONTROLS

| Action    | Key        |
|-----------|------------|
| Move      | WASD       |
| Interact  | E          |
| Flashlight| F          |
| Sprint    | Shift      |
| Flare     | Q          |
| Map       | M          |
| Log       | L          |
| Pause     | Esc        |

---

## 5. PLAYER SYSTEMS

The guard has four resources, all of which feed each other.

**Stamina** (0.0 to 1.0). Drains while sprinting, refills while you walk or stand.
Sprint runs at 1.8x walk speed but stamina drains fast and, crucially, running is
LOUD — the Warden hunts by sound. If you run the bar to zero you become
**exhausted**: you cannot run again until the bar is back past 45% of maximum, and
it refills at only half rate while winded. This is deliberate: it stops the
stutter-sprint exploit where releasing and re-pressing Shift let you run forever
on an empty bar.

**Battery** (0.0 to 1.0). Powers the flashlight. A full charge is about three
minutes of continuous use. The beam visibly weakens below 25% before it dies.
Battery cells are found in searchable containers around the mall; the office
supply cabinet always holds one so a player who burns every cell can still recover.

**Composure** (0.0 to 1.0). The guard's nerve. Drains in the dark, drains much
faster with the torch off, drains violently while the Warden is on your back, and
drains faster for each hunter within about 260 pixels. Light restores it; standing
in the security office restores it faster. Low composure slows you down (down to
84% speed) and makes you louder. The screen vignette closes in as composure falls.

**Flares** (small integer count). Thrown with Q. A burning flare is a noise and a
light source that pulls hunters off your trail — it is an escape, not a weapon. You
get two on nights 1 and 2, three on night 3, and that is all you get.

**Breathing.** The guard audibly pants, but only in two states the HUD is already
showing: **exhausted** (amber stamina bar, "legs gone") and **latched** (the Warden
riding your back, "GET IT OFF"). It never fires on low nerve, because low nerve is
a long quiet state with nothing on screen to explain it — which read as random
background noise. The first time it plays the game tells you: "That is you
breathing hard — and anything hunting you can hear it."

---

## 6. THE DUTY BOARD

Every night is an ordered list of duties. A duty is one of:

- **door** — reseal the service door with a wire panel (small minigame).
- **wires** — a camera junction has blown; re-route it (minigame).
- **breaker** — the west wing power has dropped; reset the breaker in Storage.
- **codes** — the camera server has dropped; reset it at your desk (keypad).
- **inspect** — walk to a paranormal anomaly and log it. There are six anomalies
  in the table (a stain in the Atrium, a note in the Food Court, blood in Fashion
  Hub, eyes in the Game Zone, a drag trail in Storage, a music box note in TOYBOX).
  Each inspect duty pulls its clue text and room straight from that table.
- **haul** — carry an item back to the security office to file it.

The board shows the current round plus the time it has to be walked by, and the
waypoint arrow points at it.

**Deadlines have teeth.** Every round has a window (110/65/55 minutes depending on
night). Miss it and you take a **missed round**: management logs it, a hunter is
released on the strength of it, and the board moves on. Three missed rounds and you
are relieved of duty — the shift ends in failure however healthy you are.

**Clearing the list is not the end.** When the last duty is logged the lights drop,
a hunter is released immediately, and for the rest of the night the threat cap goes
up by one and the hunter gap is cut to 45%. The night has teeth now, and the Night
Watch keeps the guard working.

---

## 7. THE NIGHT WATCH

Clearing the duty board does not end the shift — it changes it. From that point
until dawn the guard is doing the actual job: watching the mall. The mall keeps
handing them something to watch.

There are **eight incident types**, each an interactable world object with a live
objective, a waypoint and a 20-minute deadline:

1. **Techworld** — a store shutter is up. "Pull the shutter down."
2. **Beauty Co.** — the lights are on after closing. "Cut the circuit."
3. **Food Court** — a chair is scraping. "Confirm the report."
4. **Storage Room** — a crate has moved. "Check the crate."
5. **Restrooms** — water is running. "Shut the water off."
6. **TOYBOX** — a music box is playing. "Wind it down."
7. **CINEMA** — the projector is running to an empty screen. "Kill the projector."
8. **Security Office** — the camera server logged a fault. "Review the camera log."

**Standing still is the cost.** Working an incident roots the guard in place for
1.3 seconds. In a mall where the most expensive thing you can do is stop moving,
"when is it safe to do my job" becomes the whole decision.

**The office is safe from chasers, never safe from the work.** One incident kind
sends you back to your own desk. You cannot sit in the one safe room and let the
night pass: a report left unwalked costs a missed round exactly like a duty does.
That closes the hole where a guard who finished their list could idle in the office
until morning and nothing objected.

**Pacing.** Incidents run further apart while the board still has rounds on it
(gap x1.7) so you are never asked to do two jobs at once, and closer together once
the board is clear (gap x0.7) when the mall has you to itself. Only one incident is
ever open at a time, and none spawns on top of an active encounter.

---

## 8. THE HUNTERS

Everything that hunts the guard shares one brain — the **MallAgent**. It walks a
shared A* grid so it goes around walls instead of grinding into them, spends a
small moment deciding, and is always in exactly one state: PATROL, CHASE, ATTACK or
HELD. Each hunter's real character comes from what it does inside that frame, and
from the rule you have to learn to survive it.

### The Mannequin
A clothing-store display that only creeps while your beam is off it.
- **Rule:** light is the counter. Shine the torch on it and it backs away, slower
  than you can walk.
- **Two escapes:** (1) Hold the beam on it and keep walking — push it back past 470
  pixels and it gives up for good. (2) Reach the security office; it will not cross
  the threshold, and after about six seconds it loses interest entirely.
- **Feedback:** it scrapes (you hear it before you see it), turns cold pale blue
  while lit, and backs away rather than freezing.

### The Shadow Entity
A shape that works the corridors, lurking until it sees light.
- **Rule:** TURN YOUR TORCH OFF. It charges at torchlight. Kill your light and it
  loses you; walk to the office to end it. A flare pulls it off your trail entirely.
- The warning states the counter plainly: "TURN YOUR TORCH OFF. It hunts the light.
  Walk to the office."

### The Warden (Night 3 only)
Something tall that walks the corridors and hunts by sound.
- **Rule:** it does not kill on contact — it **latches**. It climbs onto your back
  and starts burning through you: the view slams shut, you slow to 72% speed, and
  the torch drains twice as fast.
- **Two ways off:** stand in a lit room (above all the security office), or drop a
  flare at your own feet. Light also slows it while it rides, so keeping the torch
  ON buys time even though a burning torch is what every other hunter is watching.
- It will not let go on its own. After 13 seconds of riding, it finishes the job.
- The warning is: "IT IS ON YOUR BACK. Reach a lit room, or drop a flare with Q."

### The Haunted Toys
Small things in the TOYBOX and CINEMA that come toward light.
- **Rule:** they come toward torchlight. Carrying a burning beam into the east wing
  is what gets you killed there.
- The TOYBOX and CINEMA each have a night where a duty sends you into them, so a
  guard working the board always crosses their trigger eventually.

### The Threat Director
From night 2 on the mall is never allowed to be empty. Every hunter_gap seconds a
fresh hunter is released, up to the night's cap. The set-pieces are the pool:
mannequin and shadow first, the Warden once its night arrives. When everything
scripted has already run tonight, the director puts the mannequin back out on the
floor rather than letting the night go quiet.

---

## 9. THE MAP

Riverview Mall, 88x62 tiles (1792 x 1984 pixels at 32 px/tile), built at runtime.
Fourteen named rooms in a three-column layout with the east wing hung off the end:

**West column:** Techworld, Books & More, Coffee Shop, Storage Room.
**Middle column:** Game Zone, Main Atrium, Food Court, Security Office.
**East column:** Fashion Hub, Beauty Co., Sports Zone, Restrooms.
**Far east wing:** TOYBOX, CINEMA — reachable only down the long corridors, the
part of the building that feels furthest from help.

Horizontal corridors run between the columns; a vertical link joins the wings. The
east wing is deliberately a long walk from the office.

Every room has hand-placed furniture, a readable overhead name sign with a worn
brass plate, wall-mounted fittings for the camera/server tasks, and at least one
searchable container. Props carry a soft shadow and mirror every other instance so
a row of identical fittings does not read as one stamped copy. Every prop is
inset from walls by a fixed margin so nothing ever looks buried in a wall.

The **security office** is the safe room: lit, never fully dark, the one place a
chaser will not follow. The camera terminal lives here, and it is where haul items
are filed.

---

## 10. LIGHTING MODEL

The whole mall sits under a single `CanvasModulate` that multiplies every canvas
item on screen, starting around (0.17, 0.2, 0.29) at 10 PM and decaying toward
(0.075, 0.085, 0.14) by dawn. The dread curve is per night, and by night 3 the mall
starts partly dark.

Because the modulate multiplies everything, a brighter sprite cannot "shine" — only
a `PointLight2D` survives it. So every meaningful glow in the game is a real
PointLight2D: the flashlight, the searchable stash glow (which appears when your
battery is low and the container holds a cell), the Game Zone incident lights, the
mall's own ceiling lights (which flicker and occasionally black out), and incident
glows.

The office is deliberately pulled back toward full brightness even deep into a
night: it is the one place that should feel safe.

Ambience volume rises with dread — a low drone that gets louder as the hours pass.

---

## 11. UI / HUD

- **Clock** — always on screen, reads in 12-hour format.
- **Night label** — the night's title.
- **Objective panel** — the current round, with the time it is due. A blank
  objective is refused by the game; if a caller has nothing to say, the board keeps
  the last real instruction rather than rendering an empty header.
- **Warning line** — a live-threat line that sits UNDER the objective, never
  replacing it. It always states the counter, not the mood. ("Hold your beam on it
  — it backs away.")
- **Waypoint** — a pulsing arrow in the world-space direction of the objective,
  with a distance readout on a dark backing pill so it never merges with the mall's
  own signage. When you are in the objective room the arrow hides.
- **Vitals** — two bars (STAMINA, NERVE) in the corner, turning red as they empty.
  "GET IT OFF" appears when the Warden is riding you.
- **Evidence counter** — the run's score, incremented every time you log a duty,
  an anomaly, or a walked round.
- **Missed rounds** — appears once you have missed one, showing strikes out of
  three.
- **Danger flash / vignette** — a red pulse and a closing vignette when something
  is hunting you, slamming shut while the Warden rides.
- **Shift log** — a scrollable timestamped record of everything that happened. The
  log dedupes: reloading a save cannot print the same duty line twice.

---

## 12. SAVE / LOAD

Autosave fires after every resolved round — duties, watches, escapes, anything that
changes the night's state — but never while something is actively hunting you. That
refusal is deliberate: a reload should not drop you back into the middle of a chase.

A save stores the clock, elapsed minutes, objective, flags, the full shift log,
tutorial status, night number and player position. It is versioned; a file from an
older layout is refused rather than read half-way and corrupted, and a broken file
is never deleted.

On restore, the night rebuilds itself and every system restores its own state. This
is where an old bug lived: inspect duties carry only a stop index in the config, and
the text and room are copied across from the anomaly table at build time. Restoring
without that step left every inspect round with a blank objective — a "Duty:" line
with nothing after it. Restore now always rebuilds the list properly first.

---

## 13. TIME AND DREAD

One accumulator advances the minute counter at the night's tick rate. Crossing an
hour fires an announcement over the mall tannoy. The announcements start as ordinary
closing notices and stop making sense long before morning:

- 10 PM: "Riverview Mall is now closed. Please make your way to the exits."
- 11 PM: "The mall is closed. Please leave the premises."
- Midnight: "Attention. Attention. Attention."
- 1 AM: "Would the night guard please report to the management office."
- 2 AM: "Thank you for shopping at Riverview."
- 3 AM: "We are open. We are open. We are open."
- 4 AM: "Please do not touch the displays."
- 5 AM: "Is anyone still there."

The tannoy keeps talking long after everyone has gone home. That is the whole tone
of the game in one system.

---

## 14. THE ENEMY OF THE PLAYER IS IDLENESS

Design law worth stating plainly, because most of the bug fixes in this game came
from it: **nothing in this game may ever let the guard win by doing nothing.**

- The duty board has deadlines.
- The night watch keeps spawning after the board is clear.
- Missed rounds of any kind count toward the same three strikes.
- The office is safe from things that chase you but never from the work itself.
- The finale takes the lights and the hunters up a gear the moment the paperwork
  is finished.

If a player could park in the security office and reach morning untouched, the game
would have no horror in it at all.

---

## 15. FILE MAP

- `scripts/game_manager.gd` — autoload "Game": clock, objectives, flags, save/load.
- `scripts/night_config.gd` — all difficulty and duty data for the three nights.
- `scripts/mall.gd` — builds the map, props, lights, doors, signs, searchables.
- `scripts/player.gd` — the guard: movement, resources, interaction.
- `scripts/encounter_manager.gd` — duties, night watch, hunter director, encounters.
- `scripts/interactable.gd` — base class for anything you press E on.
- `scripts/inspectable.gd` — flavour-text props.
- `scripts/entities/mall_agent.gd` — shared hunter brain and A* movement.
- `scripts/entities/mannequin.gd`, `shadow_entity.gd`, `warden.gd`, `haunted_toy.gd`.
- `scripts/objects/` — task items, watch items, searchables, batteries, breaker,
  flares, service doors.
- `scripts/ui/hud.gd` — clock, objective, warning, waypoint, vitals, log.
- `scripts/ui/` — main menu, pause, map screen, shift log, minigame, camera, endings.

---

*AFTER HOURS — internal design reference.*