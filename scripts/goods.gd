extends RefCounted
# What you dig up and what the forge makes of it: ores and gems, bars, and the recipes for
# both, plus the rules for packing them. Everything you carry is a plain dictionary, so it goes
# straight into the save:
#   gear       see Items
#   goods      {"kind": "good", "id", "count"}, stacking up to STACK in one slot
#   treasure   {"kind": "treasure", "id": its number in Treasures.LIST, "value": coins it sells for}

const Blocks := preload("res://scripts/blocks.gd")
const Items := preload("res://scripts/items.gd")
const Treasures := preload("res://scripts/treasures.gd")

const STACK := 20

# Everything that stacks, in the order it's listed. Ores and gems come out of the ground: `block`
# is the ground they're found in and `cells` how many cells of it you dig out for one piece.
const LIST := {
	"coal": {"name": "Coal", "plural": "Coal", "value": 2, "block": Blocks.COAL, "cells": 18,
		"color": Color(0.5, 0.5, 0.54), "text": "Fuel for the forge: every bar it smelts burns some."},
	"copper_ore": {"name": "Copper ore", "plural": "Copper ore", "value": 3, "block": Blocks.COPPER_ORE, "cells": 20,
		"color": Color(0.95, 0.55, 0.3), "text": "Rock flecked with copper. The forge turns it into copper bars."},
	"iron_ore": {"name": "Iron ore", "plural": "Iron ore", "value": 5, "block": Blocks.IRON_ORE, "cells": 22,
		"color": Color(0.8, 0.45, 0.32), "text": "Rusty and heavy. Smelt it into iron bars."},
	"silver_ore": {"name": "Silver ore", "plural": "Silver ore", "value": 9, "block": Blocks.SILVER_ORE, "cells": 24,
		"color": Color(0.86, 0.88, 0.95), "text": "Bright flecks in grey rock."},
	"amethyst": {"name": "Amethyst", "plural": "Amethysts", "value": 14, "block": Blocks.AMETHYST, "cells": 28,
		"color": Color(0.75, 0.48, 1.0), "text": "A violet crystal, worth a fair bit just as it is."},
	"gold_ore": {"name": "Gold ore", "plural": "Gold ore", "value": 18, "block": Blocks.GOLD_ORE, "cells": 26,
		"color": Color(1.0, 0.8, 0.3), "text": "Gold, glinting in the dark."},
	"ruby": {"name": "Ruby", "plural": "Rubies", "value": 30, "block": Blocks.RUBY, "cells": 32,
		"color": Color(1.0, 0.3, 0.36), "text": "Deep red and flawless."},
	"diamond": {"name": "Diamond", "plural": "Diamonds", "value": 55, "block": Blocks.DIAMOND, "cells": 36,
		"color": Color(0.7, 0.95, 1.0), "text": "The hardest thing there is. Diamond gear is made with it."},
	"copper_bar": {"name": "Copper bar", "plural": "Copper bars", "value": 9,
		"color": Color(0.86, 0.5, 0.3), "text": "For copper swords and maces."},
	"iron_bar": {"name": "Iron bar", "plural": "Iron bars", "value": 14,
		"color": Color(0.66, 0.67, 0.7), "text": "For iron tools and weapons, and for steel."},
	"steel_bar": {"name": "Steel bar", "plural": "Steel bars", "value": 22,
		"color": Color(0.6, 0.74, 0.88), "text": "Iron smelted again with coal: harder and tougher."},
	"silver_bar": {"name": "Silver bar", "plural": "Silver bars", "value": 24,
		"color": Color(0.88, 0.9, 0.96), "text": "Worth more than the ore it came from."},
	"gold_bar": {"name": "Gold bar", "plural": "Gold bars", "value": 46,
		"color": Color(1.0, 0.82, 0.32), "text": "Heavy, gleaming, and worth a lot."},
}

# Where veins of each ore turn up, in metres below the house floor, how common they are, the
# size of the lumps they're made of (metres across) and how many lumps.
const VEINS := [
	{"good": "coal", "depth": [1.5, 26.0], "weight": 30.0, "size": [0.6, 1.2], "lumps": [2, 4]},
	{"good": "copper_ore", "depth": [2.0, 18.0], "weight": 26.0, "size": [0.55, 1.1], "lumps": [2, 3]},
	{"good": "iron_ore", "depth": [7.0, 34.0], "weight": 24.0, "size": [0.55, 1.1], "lumps": [2, 3]},
	{"good": "silver_ore", "depth": [15.0, 38.0], "weight": 14.0, "size": [0.6, 1.1], "lumps": [2, 3]},
	{"good": "amethyst", "depth": [18.0, 40.0], "weight": 8.0, "size": [0.55, 1.0], "lumps": [1, 3]},
	{"good": "gold_ore", "depth": [22.0, 43.0], "weight": 10.0, "size": [0.55, 1.05], "lumps": [2, 3]},
	{"good": "ruby", "depth": [27.0, 43.0], "weight": 5.0, "size": [0.5, 0.85], "lumps": [1, 3]},
	{"good": "diamond", "depth": [29.0, 43.0], "weight": 4.0, "size": [0.45, 0.75], "lumps": [1, 2]},
]

# The forge: smelting burns coal to turn ore into bars...
const SMELT := [
	{"out": "copper_bar", "in": {"copper_ore": 2, "coal": 1}},
	{"out": "iron_bar", "in": {"iron_ore": 2, "coal": 1}},
	{"out": "steel_bar", "in": {"iron_bar": 1, "coal": 2}},
	{"out": "silver_bar", "in": {"silver_ore": 2, "coal": 1}},
	{"out": "gold_bar", "in": {"gold_ore": 2, "coal": 1}},
]
# ...and bars (and diamonds) become plain metal gear. Bows and wooden shields come from the
# workbench instead.
const FORGE := [
	{"kind": "pickaxe", "tier": 1, "in": {"iron_bar": 4}},
	{"kind": "pickaxe", "tier": 2, "in": {"steel_bar": 5}},
	{"kind": "pickaxe", "tier": 3, "in": {"steel_bar": 4, "gold_bar": 2, "diamond": 3}},
	{"kind": "sword", "tier": 0, "in": {"copper_bar": 3}},
	{"kind": "sword", "tier": 1, "in": {"iron_bar": 3}},
	{"kind": "sword", "tier": 2, "in": {"steel_bar": 4}},
	{"kind": "sword", "tier": 3, "in": {"steel_bar": 3, "gold_bar": 1, "diamond": 2}},
	{"kind": "mace", "tier": 0, "in": {"copper_bar": 4}},
	{"kind": "mace", "tier": 1, "in": {"iron_bar": 4}},
	{"kind": "mace", "tier": 2, "in": {"steel_bar": 5}},
	{"kind": "mace", "tier": 3, "in": {"steel_bar": 4, "gold_bar": 1, "diamond": 3}},
	{"kind": "shield", "tier": 1, "in": {"iron_bar": 3}},
	{"kind": "shield", "tier": 2, "in": {"steel_bar": 4}},
	{"kind": "shield", "tier": 3, "in": {"steel_bar": 3, "silver_bar": 2, "diamond": 2}},
]

static var BLOCK_GOOD := {}    # ore block -> the good it gives


static func _static_init() -> void:
	for id: String in LIST:
		if LIST[id].has("block"):
			BLOCK_GOOD[LIST[id]["block"]] = id


static func make(id: String, n := 1) -> Dictionary:
	return {"kind": "good", "id": id, "count": n}


static func is_gear(item: Dictionary) -> bool:
	return Items.KINDS.has(str(item.get("kind", "")))


static func is_good(item: Dictionary) -> bool:
	return item.get("kind", "") == "good"


static func is_treasure(item: Dictionary) -> bool:
	return item.get("kind", "") == "treasure"


# "ore" (ore and gems), "bar", "treasure" or "gear".
static func sort_of(item: Dictionary) -> String:
	if is_good(item):
		return "ore" if LIST[item["id"]].has("block") else "bar"
	if is_treasure(item):
		return "treasure"
	return "gear"


# Anything read back from a save (where every number is a float), made proper, or {}.
static func sanitize(d) -> Dictionary:
	if not d is Dictionary:
		return {}
	match str(d.get("kind", "")):
		"good":
			var id := str(d.get("id", ""))
			var n := clampi(int(d.get("count", 0)), 0, STACK)
			return make(id, n) if LIST.has(id) and n > 0 else {}
		"treasure":
			var t := int(d.get("id", -1))
			if t < 0 or t >= Treasures.LIST.size():
				return {}
			return {"kind": "treasure", "id": t, "value": maxi(0, int(d.get("value", Treasures.LIST[t]["value"])))}
	return Items.sanitize(d)


# --- Words and numbers ---------------------------------------------------------------------

static func title(item: Dictionary) -> String:
	if is_good(item):
		return LIST[item["id"]]["name"]
	if is_treasure(item):
		return Treasures.LIST[item["id"]]["name"]
	return Items.title(item)


static func color(item: Dictionary) -> Color:
	if is_good(item):
		return LIST[item["id"]]["color"]
	if is_treasure(item):
		return Treasures.RARITY_COLORS[Treasures.LIST[item["id"]]["rarity"]]
	return Items.color(item)


# What it sells for at the workbench. Gear is broken down at the anvil instead.
static func worth(item: Dictionary) -> int:
	if is_good(item):
		return int(LIST[item["id"]]["value"]) * int(item["count"])
	if is_treasure(item):
		return int(item["value"])
	return 0


static func amount(id: String, n: int) -> String:
	return "%d %s" % [n, LIST[id]["name"] if n == 1 else LIST[id]["plural"]]


# "2 Iron ore + 1 Coal"
static func needs_text(needs: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in needs:
		parts.append(amount(id, int(needs[id])))
	return " + ".join(parts)


# The pickaxe tier that digs an ore out (see Items.TIER_NAMES).
static func tier_needed(id: String) -> int:
	return Blocks.TIER[LIST[id]["block"]] if LIST[id].has("block") else 0


static func depth_of(id: String) -> Array:
	for v: Dictionary in VEINS:
		if v["good"] == id:
			return v["depth"]
	return [0.0, 0.0]


# --- Packing -----------------------------------------------------------------------------

static func count(container: Array, id: String) -> int:
	var n := 0
	for item: Dictionary in container:
		if is_good(item) and item["id"] == id:
			n += int(item["count"])
	return n


# How many more of a good fit in a container with this many slots.
static func room_for(container: Array, slots: int, id: String) -> int:
	var room := maxi(0, slots - container.size()) * STACK
	for item: Dictionary in container:
		if is_good(item) and item["id"] == id:
			room += maxi(0, STACK - int(item["count"]))
	return room


# Adds up to n of a good, topping up its stacks before starting new ones. Returns how many went
# in.
static func add(container: Array, slots: int, id: String, n: int) -> int:
	var left := n
	for item: Dictionary in container:
		if left <= 0:
			break
		if is_good(item) and item["id"] == id and int(item["count"]) < STACK:
			var k := mini(left, STACK - int(item["count"]))
			item["count"] = int(item["count"]) + k
			left -= k
	while left > 0 and container.size() < slots:
		var k := mini(left, STACK)
		container.append(make(id, k))
		left -= k
	return n - left


# Takes n of a good out, from the last stacks first. The caller checks there are enough.
static func take(container: Array, id: String, n: int) -> void:
	var left := n
	var i := container.size() - 1
	while i >= 0 and left > 0:
		var item: Dictionary = container[i]
		if is_good(item) and item["id"] == id:
			var k := mini(left, int(item["count"]))
			item["count"] = int(item["count"]) - k
			left -= k
			if int(item["count"]) <= 0:
				container.remove_at(i)
		i -= 1


# Moves an item into a container: goods top up its stacks as far as they fit (what doesn't fit
# stays in `item`), anything else needs a free slot. Returns whether all of it went in.
static func put(container: Array, slots: int, item: Dictionary) -> bool:
	if is_good(item):
		var moved := add(container, slots, item["id"], int(item["count"]))
		item["count"] = int(item["count"]) - moved
		return int(item["count"]) <= 0
	if container.size() >= slots:
		return false
	container.append(item)
	return true


# How many times over a container holds everything on a list.
static func times(container: Array, needs: Dictionary) -> int:
	var best := 1 << 30
	for id: String in needs:
		best = mini(best, count(container, id) / int(needs[id]))
	return best
