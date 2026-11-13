# Store Redesign — status

Interior-by-interior rebuild of Riverview Mall. Workflow: one store at a time,
layout planned before placement, then **verified in the running game** from the
gameplay camera before the store is marked complete.

## Visual standard (applied to every store)

- **Top-down only.** Every fixture is a sprite drawn from directly above. The old
  `prop_bookcase` / `shelf` are front elevations and must not be used in shops.
- **One palette.** Cool desaturated blue-grey, matching the mall's lighting.
- **Store-specific fixtures.** No generic shelving used to fill space.
- **Clear approach lanes.** The room's doorways stay walkable.
- **Wall-attached and correctly oriented.** A fitting backs onto the wall it
  belongs to and faces into the room — it is never left facing the camera in the
  middle of the floor. `_put(tex, cell, box, rot, margin)`: `rot` is degrees
  clockwise, `margin` is the walkable gap. Pass `margin = 0` and place the fixture
  one cell *into* its wall, and `_inset_from_walls` snaps it flush to the tiles.

## Completed (verified in-game)

| # | Room | Layout | Fixtures |
|---|------|--------|----------|
| 1 | **Books & More** | Shelving runs N–S with walkways between, display tables and a reading nook at the front, till beside the door | `book_shelf_h`, `book_shelf_v`, `book_table`, `book_checkout`, `book_chair` |
| 2 | **Beauty Co.** | Glass display counters on the floor, wall shelving, consultation vanity, display table, till | `beauty_counter`, `beauty_shelf_v`, `beauty_table`, `beauty_mirror`, `beauty_checkout`, `beauty_stand` |
| 3 | **Restrooms** | Sink runs with mirrors either side of the door, urinal run on the west wall, stall bank on the south wall, janitorial cart | `wc_stall`, `wc_urinal`, `wc_sink_row`, `wc_dryer`, `wc_cleaning` |
| 4 | **Fashion Hub** | Fitting rooms on the back wall, racks either side of a central aisle, mannequins at the door, display table, till | `fashion_fitting`, `fashion_table`, `shop_checkout` (+ `prop_rack`, `mannequin`) |
| 5 | **Coffee Shop** | Service counter with espresso machine, pastry case, tables and chairs, sofa | `cafe_counter`, `cafe_pastry`, `cafe_chair` (+ `prop_foodtable`, `prop_sofa`) |
| 6 | **Techworld** | Screen display walls on the back wall, boxed-stock shelving flush on both side walls, glass display counters, demo table, till | `tech_screen_wall`, `tech_shelf_v`, `tech_counter`, `tech_table` |
| 7 | **Game Zone** | Arcade cabinets on the back wall, change machine on the west wall, claw machine and prize counter by the door | `arcade_change`, `arcade_prize`, `arcade_claw` |
| 8 | **Food Court** | Serving counters on the back wall, round tables with chairs across the floor, tray return and condiment stand | `court_counter`, `court_tray`, `court_condiment` |
| 9 | **Sports Zone** | Shoe display wall across the back either side of the door, clothing racks and ball bins on the floor, fitting bench, till | `sport_shoe_wall`, `sport_ballbin`, `shop_checkout` |
| 10 | **Storage Room** | Pallet racking along both side walls and the back wall, stacked crates, vending machine, staff locker | `stock_shelf_v`, `stock_shelf_h` |
| 11 | **Security Office** | Monitor desk against the west wall facing into the room, staff lockers on the east wall, couch and coffee machine | `office_desk` |
| 12 | **TOYBOX** | Toy shelving down the west wall, boxed stock and play pieces on the floor, plush bins, till by the door | `toy_shelf_v`, `shop_checkout` |
| 13 | **CINEMA** | Screen across the front wall clear of the door lane, banks of seats facing it with a centre aisle, concession counter | `cinema_screen`, `cinema_seat`, `cinema_concession` |
| 14 | **Main Atrium** | Fountain and escalators, planters and benches, mall directory board flush on the west wall | `mall_directory` |

## Remaining

**None.** All 14 interiors are redesigned and verified in the running game.

Phase 5 (mall-wide inspection: transitions, scale, repeated layouts, accessibility,
layering) is the next pass, followed by the gameplay block.

## Notes

- `prop_bookcase` and `shelf` are now unused in shops (front elevations).
- New fixtures are cool-palette by construction, so they need **no** `TEX_WARM` entry.
- Verified with `run_scene` on `res://scenes/main/mall.tscn`, spawning the player in
  each room via a temporary `PLAYER_SPAWN` override.
