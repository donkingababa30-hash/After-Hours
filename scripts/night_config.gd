class_name NightConfig
extends RefCounted
## The three nights of the shift, as data.
##
## Every difficulty knob lives here so that tuning the game never means editing
## logic. Night 1 is a quiet walk with one scripted scare; by Night 3 the mall is
## permanently dark, three hunters are loose and the guard can barely run.

## Duty kinds a night can ask for:
##   door    - reseal the service door with the wire panel
##   wires   - the same panel, used to re-route a camera
##   breaker - bring the west wing back up
##   codes   - reset the camera server from a keypad
##   inspect - walk to a paranormal anomaly and log it (stop_index picks which)
##   haul    - carry an item back to the security office
##
## Every duty carries THREE pieces of text, because one run-on sentence could not
## answer both halves of the question the guard is actually asking:
##   text    - the instruction, short enough to read at a glance. WHAT to do.
##   where   - the location in words. WHERE to go.
##   detail  - the full sentence, used for the on-screen message and the shift log.
## The board shows text and where on separate lines; the log keeps detail. Writing
## one long string into all three is what produced a 140-character objective that
## ran off the side of the panel.
const NIGHTS := [
	{
		"number": 1,
		"subtitle": "PROBATION",
		"brief": "The service door is wedged open. Seal it, walk your rounds, get to 2 AM.",
		"end_minutes": 240,
		"seconds_per_minute": 2.0,
		"dread_floor": 0.0,
		"threat_speed": 0.90,
		"threats_max": 1,
		"hunter_gap": 150.0,
		"duty_deadline": 110,
		"stamina_max": 1.0,
		"stamina_drain": 0.19,
		"stamina_regen": 0.30,
		"composure_drain": 0.011,
		"flares": 2,
		"warden": false,
		"warden_from": -1,
		"duties": [
			{"kind": "door", "room": "Storage Room",
				"text": "Seal the service door",
				"where": "Service corridor, west end",
				"detail": "The service door is wedged open. Walk up to it and reroute the wire panel."},
			{"kind": "inspect", "stop_index": 0},
			{"kind": "codes", "room": "Security Office",
				"text": "Reset the camera server",
				"where": "Security Office, your desk",
				"detail": "The camera server has dropped out. Reset it at your desk."},
			{"kind": "wires", "room": "Game Zone",
				"text": "Repair the camera junction",
				"where": "Game Zone",
				"detail": "A camera junction in the Game Zone has blown. Re-route it."},
			{"kind": "inspect", "stop_index": 1},
			{"kind": "haul", "room": "Books & More", "dest": "Security Office",
				"text": "Fetch the duty logbook",
				"where": "Books & More",
				"detail": "The duty logbook is missing. Fetch it from Books & More.",
				"carry": "logbook"},
			{"kind": "breaker", "room": "Storage Room",
				"text": "Reset the west wing breaker",
				"where": "Storage Room",
				"detail": "The west wing breaker has tripped. Bring the lights back."},
			# The east wing had no duty on ANY night, so a guard working the board
			# never set foot in the TOYBOX and the Toy Creeper's room trigger could
			# never fire. The board has to walk them past it.
			{"kind": "haul", "room": "TOYBOX", "dest": "Security Office",
				"text": "Bring back the stock manifest",
				"where": "TOYBOX, east wing",
				"detail": "Stock was left unsealed in the TOYBOX. Bring the manifest back.",
				"carry": "manifest"},
			{"kind": "inspect", "stop_index": 2},
		],
	},
	{
		"number": 2,
		"subtitle": "THE ROUNDS",
		"brief": "Something in the west wing has started moving on its own. It watches the light.",
		"end_minutes": 300,
		"seconds_per_minute": 1.8,
		"dread_floor": 0.18,
		"threat_speed": 1.04,
		"threats_max": 2,
		"hunter_gap": 70.0,
		"duty_deadline": 65,
		"stamina_max": 1.0,
		"stamina_drain": 0.24,
		"stamina_regen": 0.24,
		"composure_drain": 0.014,
		"flares": 2,
		"warden": false,
		"warden_from": 205,
		"duties": [
			{"kind": "breaker", "room": "Storage Room",
				"text": "Reset the west wing breaker",
				"where": "Storage Room",
				"detail": "The west wing breaker has tripped. Bring the lights back."},
			{"kind": "inspect", "stop_index": 2},
			{"kind": "haul", "room": "Books & More", "dest": "Security Office",
				"text": "Fetch the duty logbook",
				"where": "Books & More",
				"detail": "The duty logbook is missing. Fetch it from Books & More.",
				"carry": "logbook"},
			{"kind": "wires", "room": "Storage Room",
				"text": "Repair the camera junction",
				"where": "Storage Room",
				"detail": "The service door has been forced again. Re-route the junction panel."},
			{"kind": "haul", "room": "CINEMA", "dest": "Security Office",
				"text": "Fetch the projector log",
				"where": "CINEMA, projection booth",
				"detail": "The CINEMA projector log is overdue. Fetch it from the projection booth.",
				"carry": "projector log"},
			{"kind": "inspect", "stop_index": 3},
			{"kind": "inspect", "stop_index": 5},
		],
	},
	{
		"number": 3,
		"subtitle": "THE WARDEN",
		"brief": "It has stopped hiding. It will find you, and it will not let go.",
		"end_minutes": 360,
		"seconds_per_minute": 1.7,
		"dread_floor": 0.34,
		"threat_speed": 1.14,
		"threats_max": 3,
		"hunter_gap": 45.0,
		"duty_deadline": 55,
		"stamina_max": 1.0,
		"stamina_drain": 0.30,
		"stamina_regen": 0.20,
		"composure_drain": 0.019,
		"flares": 3,
		"warden": true,
		"warden_from": 40,
		"duties": [
			{"kind": "door", "room": "Storage Room",
				"text": "Seal the service door",
				"where": "Service corridor, west end",
				"detail": "The service door is wide open. Seal it before something else comes in."},
			{"kind": "breaker", "room": "Storage Room",
				"text": "Reset the west wing breaker",
				"where": "Storage Room",
				"detail": "West wing power is down again. Reset the breaker."},
			{"kind": "codes", "room": "Security Office",
				"text": "Reset the camera server",
				"where": "Security Office, your desk",
				"detail": "The camera server is dead. Reset it at your desk."},
			{"kind": "inspect", "stop_index": 5},
			{"kind": "haul", "room": "Storage Room", "dest": "Security Office",
				"text": "File the storage manifest",
				"where": "Storage Room",
				"detail": "Retrieve the manifest from Storage and file it at your desk.",
				"carry": "manifest"},
			{"kind": "inspect", "stop_index": 2},
			{"kind": "inspect", "stop_index": 0},
		],
	},
]


## Difficulty data for a night number (1-based). Clamps into range.
static func for_night(night_number: int) -> Dictionary:
	var index := clampi(night_number - 1, 0, NIGHTS.size() - 1)
	return NIGHTS[index]


static func count() -> int:
	return NIGHTS.size()


## Total real seconds a night lasts, for menus and the devlog.
static func real_seconds(night_number: int) -> float:
	var data := for_night(night_number)
	return float(data["end_minutes"]) * float(data["seconds_per_minute"])