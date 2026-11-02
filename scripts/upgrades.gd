extends RefCounted
# Everything coins can buy at the workbench: pickaxe upgrades and things for your room.

# Each pick head digs its own tier of rock and everything softer (see Blocks.TIER).
const HEADS := [
	{"name": "Copper", "cost": 0, "color": Color(0.86, 0.5, 0.3), "digs": "dirt, sand, clay and gravel"},
	{"name": "Iron", "cost": 120, "color": Color(0.64, 0.65, 0.68), "digs": "stone"},
	{"name": "Steel", "cost": 450, "color": Color(0.58, 0.72, 0.86), "digs": "slate"},
	{"name": "Diamond", "cost": 1200, "color": Color(0.5, 0.96, 1.0), "digs": "deeprock"},
]
# Swing speed multiplier.
const GRIPS := [
	{"name": "Plain grip", "cost": 0, "speed": 1.0},
	{"name": "Leather grip", "cost": 90, "speed": 1.35},
	{"name": "Balanced grip", "cost": 260, "speed": 1.75},
	{"name": "Master's grip", "cost": 650, "speed": 2.25},
]
# How far around the point you hit each swing clears, in cubes.
const SIZES := [
	{"name": "Small head", "cost": 0, "radius": 2.0},
	{"name": "Wide head", "cost": 110, "radius": 2.6},
	{"name": "Broad head", "cost": 320, "radius": 3.3},
	{"name": "Huge head", "cost": 800, "radius": 4.2},
]
const PICKAXE := {"head": HEADS, "grip": GRIPS, "size": SIZES}

const ROOM := [
	{"id": "plants", "name": "Potted plants", "cost": 40, "text": "A bit of green in the corners."},
	{"id": "lanterns", "name": "Wall lanterns", "cost": 80, "text": "Four warm lanterns on the walls."},
	{"id": "rug", "name": "Woven rug", "cost": 120, "text": "Red and gold, soft underfoot."},
	{"id": "shelves", "name": "Trophy shelves", "cost": 200, "text": "Shows one of every treasure you've found."},
	{"id": "bed", "name": "Cozy bed", "cost": 260, "text": "For dreaming about the next big find."},
	{"id": "books", "name": "Bookshelf", "cost": 360, "text": "Old maps and stories of lost treasure."},
	{"id": "fireplace", "name": "Stone fireplace", "cost": 500, "text": "A crackling fire to come home to."},
	{"id": "panelling", "name": "Wood panelling", "cost": 700, "text": "Polished panels and green wallpaper."},
	{"id": "chandelier", "name": "Golden chandelier", "cost": 1000, "text": "Because you can afford it now."},
]


# "an Iron", "a Steel": the head's name with its article.
static func head_name(tier: int) -> String:
	var name: String = HEADS[tier]["name"]
	return ("an " if "AEIOU".contains(name[0]) else "a ") + name


static func room_index(id: String) -> int:
	for i in ROOM.size():
		if ROOM[i]["id"] == id:
			return i
	return -1
