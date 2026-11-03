extends RefCounted
# What you dig up and what the forge makes of it: ores and gems, bars, the recipes for smelting
# and for improving gear, scrolls, and the rules for packing it all. Everything you carry is a
# plain dictionary, so it goes straight into the save:
#   gear       see Items
#   goods      {"kind": "good", "id", "count"}, stacking up to STACK in one slot
#   treasure   {"kind": "treasure", "id": its number in Treasures.LIST, "value": coins it sells for}
#   scroll     {"kind": "scroll", "id": the affix it teaches (see Items.AFFIXES), "value", "worth"}

const Blocks := preload("res://scripts/blocks.gd")
const Items := preload("res://scripts/items.gd")
const Treasures := preload("res://scripts/treasures.gd")

const STACK := 20
const SCROLL_COLOR := Color(0.98, 0.86, 0.58)

# Everything that stacks, in the order it's listed. Ores and gems come out of the ground: `block`
# is the ground they're found in and `cells` how many cells of it you dig out for one piece.
const LIST := {
	"coal": {"name": "Coal", "plural": "Coal", "value": 2, "block": Blocks.COAL, "cells": 18,
		"color": Color(0.5, 0.5, 0.54), "text": "Fuel for the forge: every bar it smelts burns some."},
	"copper_ore": {"name": "Copper ore", "plural": "Copper ore", "value": 3, "block": Blocks.COPPER_ORE, "cells": 20,
		"color": Color(0.95, 0.55, 0.3), "text": "Rock flecked with copper. The forge turns it into copper bars."},
	"iron_ore": {"name": "Iron ore", "plural": "Iron ore", "value": 5, "block": Blocks.IRON_ORE, "cells": 22,
		"color": Color(0.8, 0.45, 0.32), "text": "Rusty and heavy. Smelt it into iron bars, then steel."},
	"silver_ore": {"name": "Silver ore", "plural": "Silver ore", "value": 9, "block": Blocks.SILVER_ORE, "cells": 24,
		"color": Color(0.86, 0.88, 0.95), "text": "Bright flecks in grey rock."},
	"amethyst": {"name": "Amethyst", "plural": "Amethysts", "value": 14, "block": Blocks.AMETHYST, "cells": 28,
		"color": Color(0.75, 0.48, 1.0), "text": "A violet crystal, worth a fair bit just as it is."},
	"gold_ore": {"name": "Gold ore", "plural": "Gold ore", "value": 18, "block": Blocks.GOLD_ORE, "cells": 26,
		"color": Color(1.0, 0.8, 0.3), "text": "Gold, glinting in the dark. Gold gear is better than steel."},
	"ruby": {"name": "Ruby", "plural": "Rubies", "value": 30, "block": Blocks.RUBY, "cells": 32,
		"color": Color(1.0, 0.3, 0.36), "text": "Deep red and flawless."},
	"diamond": {"name": "Diamond", "plural": "Diamonds", "value": 55, "block": Blocks.DIAMOND, "cells": 36,
		"color": Color(0.7, 0.95, 1.0), "text": "The hardest thing there is, nearly. Gold gear set with diamonds becomes diamond gear."},
	"mithril_ore": {"name": "Mithril ore", "plural": "Mithril ore", "value": 80, "block": Blocks.MITHRIL_ORE, "cells": 36,
		"color": Color(0.62, 0.86, 1.0), "text": "Light as a feather and harder than diamond. Only found far down."},
	"sapphire": {"name": "Sapphire", "plural": "Sapphires", "value": 110, "block": Blocks.SAPPHIRE, "cells": 40,
		"color": Color(0.35, 0.52, 1.0), "text": "A blue so deep it looks wet."},
	"adamant_ore": {"name": "Adamant ore", "plural": "Adamant ore", "value": 150, "block": Blocks.ADAMANT_ORE, "cells": 40,
		"color": Color(0.95, 0.35, 0.6), "text": "Dark red metal that never chips. It takes a mithril pickaxe to break it out."},
	"emerald": {"name": "Emerald", "plural": "Emeralds", "value": 210, "block": Blocks.EMERALD, "cells": 44,
		"color": Color(0.3, 0.92, 0.5), "text": "Green fire in the rock."},
	"starmetal_ore": {"name": "Starmetal ore", "plural": "Starmetal ore", "value": 300, "block": Blocks.STARMETAL_ORE, "cells": 44,
		"color": Color(1.0, 0.95, 0.72), "text": "It glows by itself. Nobody knows how it got down here."},
	"copper_bar": {"name": "Copper bar", "plural": "Copper bars", "value": 9,
		"color": Color(0.86, 0.5, 0.3), "text": "Worth more than the ore it came from."},
	"iron_bar": {"name": "Iron bar", "plural": "Iron bars", "value": 14,
		"color": Color(0.66, 0.67, 0.7), "text": "Improves copper gear to iron, and smelts again into steel."},
	"steel_bar": {"name": "Steel bar", "plural": "Steel bars", "value": 22,
		"color": Color(0.6, 0.74, 0.88), "text": "Iron smelted again with coal: harder and tougher."},
	"silver_bar": {"name": "Silver bar", "plural": "Silver bars", "value": 24,
		"color": Color(0.88, 0.9, 0.96), "text": "Worth more than the ore it came from."},
	"gold_bar": {"name": "Gold bar", "plural": "Gold bars", "value": 46,
		"color": Color(1.0, 0.82, 0.32), "text": "Heavy, gleaming, and worth a lot. Improves steel gear to gold."},
	"mithril_bar": {"name": "Mithril bar", "plural": "Mithril bars", "value": 190,
		"color": Color(0.66, 0.88, 1.0), "text": "Improves diamond gear to mithril."},
	"adamant_bar": {"name": "Adamant bar", "plural": "Adamant bars", "value": 360,
		"color": Color(0.95, 0.38, 0.62), "text": "Improves mithril gear to adamant."},
	"starmetal_bar": {"name": "Starmetal bar", "plural": "Starmetal bars", "value": 700,
		"color": Color(1.0, 0.96, 0.78), "text": "The best there is. Improves adamant gear to starmetal."},
}

# Where veins of each ore turn up, in metres below the house floor, how common they are, the
# size of the lumps they're made of (metres across) and how many lumps.
const VEINS := [
	{"good": "coal", "depth": [1.5, 60.0], "weight": 30.0, "size": [0.6, 1.2], "lumps": [2, 4]},
	{"good": "coal", "depth": [60.0, 10000.0], "weight": 12.0, "size": [0.7, 1.3], "lumps": [2, 4]},
	{"good": "copper_ore", "depth": [2.0, 40.0], "weight": 26.0, "size": [0.55, 1.1], "lumps": [2, 3]},
	{"good": "iron_ore", "depth": [6.0, 160.0], "weight": 24.0, "size": [0.55, 1.1], "lumps": [2, 3]},
	{"good": "silver_ore", "depth": [15.0, 320.0], "weight": 14.0, "size": [0.6, 1.1], "lumps": [2, 3]},
	{"good": "amethyst", "depth": [20.0, 450.0], "weight": 8.0, "size": [0.55, 1.0], "lumps": [1, 3]},
	{"good": "gold_ore", "depth": [40.0, 900.0], "weight": 12.0, "size": [0.55, 1.05], "lumps": [2, 3]},
	{"good": "ruby", "depth": [60.0, 1400.0], "weight": 6.0, "size": [0.5, 0.9], "lumps": [1, 3]},
	{"good": "diamond", "depth": [120.0, 2800.0], "weight": 6.0, "size": [0.5, 0.85], "lumps": [1, 3]},
	{"good": "mithril_ore", "depth": [280.0, 5000.0], "weight": 10.0, "size": [0.55, 1.05], "lumps": [2, 3]},
	{"good": "sapphire", "depth": [500.0, 7000.0], "weight": 5.0, "size": [0.5, 0.85], "lumps": [1, 3]},
	{"good": "adamant_ore", "depth": [700.0, 10000.0], "weight": 9.0, "size": [0.55, 1.05], "lumps": [2, 3]},
	{"good": "emerald", "depth": [1500.0, 10000.0], "weight": 4.0, "size": [0.5, 0.85], "lumps": [1, 3]},
	{"good": "starmetal_ore", "depth": [1800.0, 10000.0], "weight": 7.0, "size": [0.55, 1.05], "lumps": [2, 3]},
]

# The forge: smelting burns coal to turn ore into bars...
const SMELT := [
	{"out": "copper_bar", "in": {"copper_ore": 2, "coal": 1}},
	{"out": "iron_bar", "in": {"iron_ore": 2, "coal": 1}},
	{"out": "steel_bar", "in": {"iron_bar": 1, "coal": 2}},
	{"out": "silver_bar", "in": {"silver_ore": 2, "coal": 1}},
	{"out": "gold_bar", "in": {"gold_ore": 2, "coal": 1}},
	{"out": "mithril_bar", "in": {"mithril_ore": 2, "coal": 2}},
	{"out": "adamant_bar", "in": {"adamant_ore": 2, "coal": 3}},
	{"out": "starmetal_bar", "in": {"starmetal_ore": 2, "coal": 4}},
]
# ...and bars, gems and coins improve your gear a step: what it takes to reach each tier (see
# Items.MATERIALS). Wooden gear can't be improved, and copper is where metal gear starts.
const UPGRADES := [
	{},
	{},
	{"in": {"iron_bar": 4}, "coins": 60},
	{"in": {"steel_bar": 5}, "coins": 150},
	{"in": {"gold_bar": 5, "steel_bar": 2}, "coins": 400},
	{"in": {"diamond": 4, "gold_bar": 3}, "coins": 900},
	{"in": {"mithril_bar": 5, "diamond": 2}, "coins": 2000},
	{"in": {"adamant_bar": 5, "sapphire": 3}, "coins": 4500},
	{"in": {"starmetal_bar": 5, "emerald": 3}, "coins": 10000},
]

static var BLOCK_GOOD := {}    # ore block -> the good it gives


static func _static_init() -> void:
	for id: String in LIST:
		if LIST[id].has("block"):
			BLOCK_GOOD[LIST[id]["block"]] = id


static func make(id: String, n := 1) -> Dictionary:
	return {"kind": "good", "id": id, "count": n}


static func make_scroll(id: String, value: int, worth: int) -> Dictionary:
	return {"kind": "scroll", "id": id, "value": value, "worth": worth}


static func is_gear(item: Dictionary) -> bool:
	return Items.KINDS.has(str(item.get("kind", "")))


static func is_good(item: Dictionary) -> bool:
	return item.get("kind", "") == "good"


static func is_treasure(item: Dictionary) -> bool:
	return item.get("kind", "") == "treasure"


static func is_scroll(item: Dictionary) -> bool:
	return item.get("kind", "") == "scroll"


# "ore" (ore and gems), "bar", "treasure", "scroll" or "gear".
static func sort_of(item: Dictionary) -> String:
	if is_good(item):
		return "ore" if LIST[item["id"]].has("block") else "bar"
	if is_treasure(item):
		return "treasure"
	if is_scroll(item):
		return "scroll"
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
		"scroll":
			var id := str(d.get("id", ""))
			if not Items.SCROLL_AFFIXES.has(id):
				return {}
			return make_scroll(id, int(d.get("value", Items.AFFIXES[id]["min"])), maxi(0, int(d.get("worth", 0))))
	return Items.sanitize(d)


# --- Words and numbers ---------------------------------------------------------------------

static func title(item: Dictionary) -> String:
	if is_good(item):
		return LIST[item["id"]]["name"]
	if is_treasure(item):
		return Treasures.LIST[item["id"]]["name"]
	if is_scroll(item):
		return "Scroll of %s" % Items.AFFIXES[item["id"]]["scroll"]
	return Items.title(item)


static func color(item: Dictionary) -> Color:
	if is_good(item):
		return LIST[item["id"]]["color"]
	if is_treasure(item):
		return Treasures.RARITY_COLORS[Treasures.LIST[item["id"]]["rarity"]]
	if is_scroll(item):
		return SCROLL_COLOR
	return Items.color(item)


# What it sells for at the workbench. Gear is broken down at the anvil instead.
static func worth(item: Dictionary) -> int:
	if is_good(item):
		return int(LIST[item["id"]]["value"]) * int(item["count"])
	if is_treasure(item):
		return int(item["value"])
	if is_scroll(item):
		return int(item["worth"])
	return 0


# What a scroll teaches, in words: "+6% of the damage dealt..."
static func scroll_text(item: Dictionary) -> String:
	return Items.affix_text({"id": item["id"], "value": item["value"]})


static func amount(id: String, n: int) -> String:
	return "%d %s" % [n, LIST[id]["name"] if n == 1 else LIST[id]["plural"]]


# "2 Iron ore + 1 Coal"
static func needs_text(needs: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in needs:
		parts.append(amount(id, int(needs[id])))
	return " + ".join(parts)


# The pickaxe tier that digs an ore out (see Items.MATERIALS).
static func tier_needed(id: String) -> int:
	return Blocks.TIER[LIST[id]["block"]] if LIST[id].has("block") else 0


# Where an ore turns up, from the top of its first vein to the bottom of its last.
static func depth_of(id: String) -> Array:
	var out := []
	for v: Dictionary in VEINS:
		if v["good"] == id:
			if out.is_empty():
				out = [v["depth"][0], v["depth"][1]]
			else:
				out = [minf(out[0], v["depth"][0]), maxf(out[1], v["depth"][1])]
	return out if not out.is_empty() else [0.0, 0.0]


# Every ore and gem once, in the order they turn up.
static func ore_ids() -> Array[String]:
	var out: Array[String] = []
	for v: Dictionary in VEINS:
		if not out.has(v["good"]):
			out.append(v["good"])
	return out


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
