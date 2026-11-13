# AFTER HOURS — Enemy Mechanics Reference

Every hunter in the game is built on one shared brain (the `MallAgent`) that walks
the mall's A* grid, so nothing grinds into a wall. What makes each one distinct is
the rule the player has to learn to survive it. This document describes what is
actually implemented in code — if it is written here, it exists in the game.

Base numbers are shown at their default; every hunter's speed is multiplied by the
night's `threat_speed` (0.90 / 1.04 / 1.14 for nights 1–3). The guard walks at
**118 px/s** and sprints at **1.8x** that (about 212 px/s).

---

## 1. THE MANNEQUIN

**Visual.** A pale shop-display figure in a dark suit, faintly banded. It turns
cold pale-blue while your beam is on it.

**Where and when.** Fashion Hub is its home, but the threat director can release it
near the guard anywhere on the map from night 1 onward.

**Movement & behaviour.**
- Two states: **CHASE** (creeping toward the guard) while your beam is off it, and
  **HELD** while your beam is on it.
- Move speed 132. While HELD it *retreats* at 58 — deliberately slower than the
  guard walks, so a held mannequin is always being pushed away.
- It paths around racks and shelves, so hiding behind furniture does not save you.

**Detection.** It does not need to see you — it always knows where you are. The
only question is whether your light is on it.

**Danger.** Reaching the guard (catch radius 26) is an instant fail.

**Weaknesses.**
- Your flashlight beam, out to 240 px within a 0.9-radian half-angle, freezes it
  into HELD and makes it give ground.
- It cannot enter the security office.

**Player counterplay.**
- **Hold the beam on it and walk.** Push it past 470 px and keep it there for 1.5 s
  and it gives up permanently.
- **Or reach the security office.** Stand inside for 6 seconds and it loses
  interest completely.
- A flare's noise will pull it off you briefly like any other hunter.

**What to avoid.** Turning your back on it with the torch off — it closes fast.

**Strategy.** Light it, keep facing it, and back away along a corridor. Never let it
get between you and the office.

---

## 2. THE SHADOW ENTITY

**Visual.** A soft dark shape that drifts the corridors. It tints red the moment it
locks on.

**Where and when.** Released by the director from night 1 (night 1 leads with the
mannequin; nights 2–3 lead with the shadow). It patrols the three main corridor
lanes.

**Movement & behaviour.**
- **PATROL** at 62 px/s when it has no idea where you are, drifting between corridor
  waypoints.
- **CHASE** at 140 px/s once it senses you or you shine light at it.
- Sense range 520 px; it also turns aggressive if you are within 80 px with the
  torch on.

**Detection.** Light is its trigger: being inside your beam cone (300 px, 0.85 rad)
or standing in it too close flips it to aggressive for 1.5 s.

**Danger.** A catch is an instant fail. It is the fastest hunter in the game and it
works the corridors you have to walk.

**Weaknesses.**
- It hunts the light. Kill your torch and it loses the thread.
- A flare completely pulls it off your trail (it goes to investigate the noise).
- It cannot enter the security office.

**Player counterplay.**
- **Turn your torch off.** This is the primary counter and the game says so.
- **Drop a flare (Q)** if it is already charging — it will divert to the flare.
- **Walk to the security office** to end the encounter.

**What to avoid.** Running down a long corridor with your torch up — that is exactly
the conditions it charges under. Also, your torch-off state drains composure faster,
so pick your moment.

**Strategy.** The shadow and the mannequin have opposite rules: light beats the
mannequin, dark beats the shadow. If both are loose, alternate — douse for the
shadow, then relight to push the mannequin.

---

## 3. THE WARDEN (the tall one)

**Visual.** A very tall, gaunt silhouette — near-black with a pale, featureless head
and long limbs. **This design is preserved exactly.**

**Where and when.** Night 2, late (once the shift passes the 205-minute mark), and
night 3 almost immediately (from the 40-minute mark). It never appears on night 1.

**Movement & behaviour.**
- **PATROL** at 48 px/s along the three corridor lanes, otherwise **CHASE** at
  118 px/s.
- It hunts **by sound**, not by sight. Its hearing range is 430 px, stretched by how
  loud you are: sprinting (noise 1.0) makes it hear you from much farther than
  standing still (noise 0).
- **It does not kill on contact — it latches.** It climbs onto your back.

**Detection.** Noise. Sprinting is the loudest thing you can do; walking is quieter;
standing still is silent. Low composure also makes you louder.

**Danger — the latch.** Once on your back (ride offset 22 px behind you):
- your view slams shut (full vignette, pulsing),
- you slow to 72% speed,
- the torch drains twice as fast,
- it whispers as it rides,
- and it has a **13-second timer**. When that runs out, it finishes the job.

**Weaknesses.**
- Light hurts it: while it rides, a burning torch makes its timer run at only 55%
  speed, buying you time.
- **Standing in a lit room — above all the security office — makes it release you.**
- **A flare at your own feet makes it release you.**

**Player counterplay.**
- Hear the heavy footfalls and **stand still** — it loses your noise and goes back to
  patrolling.
- If it latches: reach a lit room (the office is guaranteed) **or drop a flare**.
- Keep the torch on *while it rides* to slow its timer — even though a burning torch
  is what draws everything else.

**What to avoid.** Sprinting to escape it — its hearing range scales with your noise,
so running is how it finds you. Panicking into the dark is the worst option.

**Strategy.** Walk, do not run. If you hear it near, freeze. If it gets you, make for
the office; you have 13 seconds and light is on your side.

---

## 4. THE HAUNTED TOYS / TOY CREEPER

**Visual.** A small wind-up clockwork creature: a riveted metal body with a key
winding slowly on its back and a skull-like face. **This design is preserved
exactly.**

**Where and when.** The east wing — the TOYBOX and the CINEMA. It wakes when the
guard enters either room after the night's gate: 80 minutes (night 1), 45 (night 2),
20 (night 3).

**Movement & behaviour.**
- **PATROL** at 54 px/s, circling its home shelves, otherwise **CHASE** at 108 px/s
  toward the light.
- **It winds up before it can hunt.** For the first 2.5 seconds after it appears it
  only patrols and its sprite sits dimmed — the audible, visible warning. Two wake
  per encounter (not three), spawned 300–520 px away, so the wind-up window is real.

**Detection.** Light. If your torch is burning within 300 px — or it is within
130 px of you — it hunts.

**Danger.** A catch at ankle height is an instant fail.

**Weaknesses.**
- It is drawn to light and lost without it. **Kill your flashlight and it winds down
  and loses interest.**
- Leaving the east wing ends the encounter — step back into the corridor and it
  resolves.

**Player counterplay.**
- When you hear the winding creak and see it dimmed, **douse the torch** — it will
  not find you.
- Or simply **leave the room**; the encounter ends when you cross the threshold.

**What to avoid.** Walking into the east wing with the torch blazing — that is a
beacon to two of them at once.

**Strategy.** Treat the east wing as a torch-off zone. Go in dark, do what you came
for, get out. If one wakes while your torch is on, kill the light and back out.

---

## Reading the cues

| Cue | Means |
|-----|-------|
| Ceramic scraping | A mannequin is near |
| Cold exhalation + red tint | The shadow has seen your light |
| Heavy, slow footfalls | The Warden is close — volume is distance |
| Whispering on your back | The Warden has latched — 13 seconds |
| A winding creak + a dimmed toy | A toy is winding up — you have ~2.5 s |
| Screen closing in, pulsing | Composure gone, or something is riding you |

## Design intent

Each hunter teaches exactly one rule, and the rules conflict on purpose:

- **Mannequin** — *light beats it.*
- **Shadow** — *dark beats it.*
- **Warden** — *silence beats it; light buys mercy.*
- **Toys** — *dark beats them; leave the wing.*

Because the mannequin and the shadow want opposite light states, a night with both
loose forces the guard to switch tactics on the move. The Warden adds a third axis —
noise — so a guard sprinting to escape the shadow is the loudest possible target for
the Warden. No two enemies share a counter.