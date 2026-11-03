extends RefCounted
# Everything coins can buy at the workbench: wooden gear, explosives, a bigger pack, a bigger
# house, decorations and furniture.

# Wooden gear the workbench sells. Everything better turns up in hidden rooms, and the forge
# improves it.
const GEAR_PRICES := {"sword": 25, "shield": 70}

const SUPPLIES := [
	{"id": "dynamite", "name": "Dynamite", "amount": 1, "cost": 25, "text": "Blows a 2.5 m hole through anything up to stone."},
	{"id": "charge", "name": "Blasting charge", "amount": 1, "cost": 90, "text": "A 4 m blast that breaks even deeprock."},
]
# Radius in metres; tier is the hardest rock the blast breaks (see Blocks.TIER).
const EXPLOSIVES := {
	"dynamite": {"name": "Dynamite", "radius": 1.25, "tier": 2, "damage": 60.0, "fuse": 2.0, "color": Color(0.8, 0.18, 0.12)},
	"charge": {"name": "Blasting charge", "radius": 2.0, "tier": 4, "damage": 110.0, "fuse": 2.6, "color": Color(0.3, 0.32, 0.36)},
}
const EXPLOSIVE_ORDER := ["dynamite", "charge"]

# Your pack's slots. Ore, gems and bars stack up to Goods.STACK in a slot; gear, treasure and
# scrolls take a slot each.
const PACKS := [
	{"name": "Satchel", "cost": 0, "slots": 8},
	{"name": "Sturdy pack", "cost": 150, "slots": 12},
	{"name": "Miner's pack", "cost": 450, "slots": 16},
	{"name": "Expedition pack", "cost": 1200, "slots": 24},
]
const WORKSHOP := {"pack": PACKS}
# What 0.5's pickaxe grips and heads cost, given back when a save from then is loaded: every
# pickaxe's material sets how fast it digs and how big a dent it leaves now.
const OLD_GRIP_COSTS := [0, 90, 350, 1000]
const OLD_SIZE_COSTS := [0, 110, 430, 1230]

# Inside size in cubes (x by z). The north wall, with the door to the stairs, stays put.
const HOUSE_TIERS := [
	{"name": "Cosy room", "size": Vector2i(64, 64), "cost": 0, "text": "8 by 8 m."},
	{"name": "Bigger room", "size": Vector2i(96, 80), "cost": 400, "text": "12 by 10 m: space for a few more things."},
	{"name": "Hall", "size": Vector2i(120, 96), "cost": 1200, "text": "15 by 12 m."},
	{"name": "Great hall", "size": Vector2i(144, 112), "cost": 3000, "text": "18 by 14 m: space for everything."},
]

const DECOR := [
	{"id": "plants", "name": "Potted plants", "cost": 40, "text": "A bit of green in the corners."},
	{"id": "lanterns", "name": "Wall lanterns", "cost": 80, "text": "Warm lanterns all around the walls."},
	{"id": "rug", "name": "Woven rug", "cost": 120, "text": "Red and gold, soft underfoot."},
	{"id": "shelves", "name": "Trophy shelves", "cost": 200, "text": "Shows one of every treasure you've found."},
	{"id": "books", "name": "Bookshelf", "cost": 360, "text": "Old maps and stories of lost treasure."},
	{"id": "fireplace", "name": "Stone fireplace", "cost": 500, "text": "A crackling fire to come home to."},
	{"id": "panelling", "name": "Wood panelling", "cost": 700, "text": "Polished panels and green wallpaper."},
	{"id": "chandelier", "name": "Golden chandelier", "cost": 1000, "text": "Because you can afford it now."},
]

# Furniture you place yourself. Size in cubes: width, height and depth before it's turned.
const FURNITURE := {
	"bed": {"name": "Bed", "cost": 250, "size": Vector3i(10, 8, 18), "verb": "Sleep",
		"text": "Sleep to heal and wake up well rested: +25% stamina for 10 minutes. You also come round here after a knockout."},
	"chest": {"name": "Storage chest", "cost": 150, "size": Vector3i(10, 7, 6), "slots": 15, "verb": "Open",
		"text": "15 slots for anything you want to keep: gear, ore, bars or treasure."},
	"wardrobe": {"name": "Wardrobe", "cost": 450, "size": Vector3i(12, 18, 6), "slots": 30, "verb": "Open",
		"text": "30 slots for anything you want to keep: gear, ore, bars or treasure."},
	"anvil": {"name": "Anvil", "cost": 600, "size": Vector3i(8, 7, 5), "verb": "Use the anvil",
		"text": "Reforge an affix on your gear, or break gear down into coins."},
	"dummy": {"name": "Training dummy", "cost": 100, "size": Vector3i(8, 15, 6), "verb": "",
		"text": "Hit it to see how hard you hit."},
	"map": {"name": "Map table", "cost": 800, "size": Vector3i(12, 8, 8), "verb": "Read the map",
		"text": "Shows the hidden rooms around where you've been digging, and lets you track one."},
}
const FURNITURE_ORDER := ["bed", "chest", "wardrobe", "anvil", "dummy", "map"]


static func decor_index(id: String) -> int:
	for i in DECOR.size():
		if DECOR[i]["id"] == id:
			return i
	return -1


static func supply(id: String) -> Dictionary:
	for s: Dictionary in SUPPLIES:
		if s["id"] == id:
			return s
	return {}
