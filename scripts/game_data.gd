extends RefCounted
## Static game content: tiles, items, tools, world objects, buildables and recipes.

const TILE := 32
const RUN_SECONDS := 300.0

# Tile types. A vein is rock with ore in it; which ore is stored per tile by the area.
const T_VOID := 0
const T_GRASS := 1
const T_PATH := 2
const T_WATER := 3
const T_THICKET := 4
const T_CAVE_FLOOR := 5
const T_CAVE_WALL := 6
const T_VEIN := 7
const T_PLANKS := 8
const T_HOUSE_WALL := 9

const SOLID_TILES := [T_VOID, T_WATER, T_THICKET, T_CAVE_WALL, T_VEIN, T_HOUSE_WALL]

const TIER_NAMES := ["Stone", "Copper", "Iron", "Silver", "Gold"]

const ITEMS := {
	"wood": {"name": "Wood", "icon": "log", "color": Color(0.6, 0.4, 0.22)},
	"handle": {"name": "Tool Handle", "icon": "handle", "color": Color(0.74, 0.54, 0.32)},
	"rock": {"name": "Rock", "icon": "stone", "color": Color(0.6, 0.6, 0.62)},
	"coal": {"name": "Coal", "icon": "lump", "color": Color(0.17, 0.17, 0.19)},
	"copper_ore": {"name": "Copper Ore", "icon": "ore", "color": Color(0.9, 0.52, 0.26)},
	"iron_ore": {"name": "Iron Ore", "icon": "ore", "color": Color(0.74, 0.47, 0.38)},
	"silver_ore": {"name": "Silver Ore", "icon": "ore", "color": Color(0.85, 0.9, 0.96)},
	"gold_ore": {"name": "Gold Ore", "icon": "ore", "color": Color(1.0, 0.82, 0.22)},
	"copper_bar": {"name": "Copper Bar", "icon": "bar", "color": Color(0.9, 0.52, 0.26)},
	"iron_bar": {"name": "Iron Bar", "icon": "bar", "color": Color(0.72, 0.74, 0.78)},
	"silver_bar": {"name": "Silver Bar", "icon": "bar", "color": Color(0.88, 0.92, 0.98)},
	"gold_bar": {"name": "Gold Bar", "icon": "bar", "color": Color(1.0, 0.82, 0.22)},
}
const ITEM_ORDER := [
	"wood", "handle", "rock", "coal", "copper_ore", "iron_ore", "silver_ore", "gold_ore",
	"copper_bar", "iron_bar", "silver_bar", "gold_bar",
]

# Tools are hit with left click. "kind" decides what they can hit, "tier" how hard a thing
# they can break. Add new tools here; anything with a matching "tool" field can be hit.
const TOOLS := {
	"stone_pickaxe": {"name": "Stone Pickaxe", "kind": "pickaxe", "tier": 0, "power": 1.0, "head": Color(0.55, 0.55, 0.58), "recipe": {}},
	"copper_pickaxe": {"name": "Copper Pickaxe", "kind": "pickaxe", "tier": 1, "power": 1.6, "head": Color(0.9, 0.52, 0.26), "recipe": {"handle": 1, "copper_bar": 3}},
	"iron_pickaxe": {"name": "Iron Pickaxe", "kind": "pickaxe", "tier": 2, "power": 2.4, "head": Color(0.72, 0.74, 0.78), "recipe": {"handle": 1, "iron_bar": 3}},
	"silver_pickaxe": {"name": "Silver Pickaxe", "kind": "pickaxe", "tier": 3, "power": 3.4, "head": Color(0.88, 0.92, 0.98), "recipe": {"handle": 1, "silver_bar": 3}},
	"gold_pickaxe": {"name": "Gold Pickaxe", "kind": "pickaxe", "tier": 4, "power": 5.0, "head": Color(1.0, 0.82, 0.22), "recipe": {"handle": 1, "gold_bar": 3}},
	"stone_axe": {"name": "Stone Axe", "kind": "axe", "tier": 0, "power": 1.0, "head": Color(0.55, 0.55, 0.58), "recipe": {}},
	"copper_axe": {"name": "Copper Axe", "kind": "axe", "tier": 1, "power": 1.6, "head": Color(0.9, 0.52, 0.26), "recipe": {"handle": 1, "copper_bar": 3}},
	"iron_axe": {"name": "Iron Axe", "kind": "axe", "tier": 2, "power": 2.4, "head": Color(0.72, 0.74, 0.78), "recipe": {"handle": 1, "iron_bar": 3}},
	"silver_axe": {"name": "Silver Axe", "kind": "axe", "tier": 3, "power": 3.4, "head": Color(0.88, 0.92, 0.98), "recipe": {"handle": 1, "silver_bar": 3}},
	"gold_axe": {"name": "Gold Axe", "kind": "axe", "tier": 4, "power": 5.0, "head": Color(1.0, 0.82, 0.22), "recipe": {"handle": 1, "gold_bar": 3}},
}
const TOOL_LINES := {
	"pickaxe": ["stone_pickaxe", "copper_pickaxe", "iron_pickaxe", "silver_pickaxe", "gold_pickaxe"],
	"axe": ["stone_axe", "copper_axe", "iron_axe", "silver_axe", "gold_axe"],
}
const STARTING_TOOLS := ["stone_pickaxe", "stone_axe"]

# Ore veins running through the mine's rock.
const VEINS := {
	"coal": {"name": "Coal Vein", "item": "coal", "tier": 0, "hp": 3.0, "drop": [1, 3]},
	"copper": {"name": "Copper Vein", "item": "copper_ore", "tier": 0, "hp": 4.0, "drop": [1, 2]},
	"iron": {"name": "Iron Vein", "item": "iron_ore", "tier": 1, "hp": 6.0, "drop": [1, 2]},
	"silver": {"name": "Silver Vein", "item": "silver_ore", "tier": 2, "hp": 8.0, "drop": [1, 2]},
	"gold": {"name": "Gold Vein", "item": "gold_ore", "tier": 3, "hp": 10.0, "drop": [1, 2]},
}

# Ore odds per mine depth (the last entry is used for anything deeper).
const MINE_FLOORS := [
	{"coal": 40, "copper": 45, "iron": 15},
	{"coal": 35, "copper": 30, "iron": 30, "silver": 5},
	{"coal": 30, "copper": 15, "iron": 35, "silver": 15, "gold": 5},
	{"coal": 25, "copper": 5, "iron": 30, "silver": 25, "gold": 15},
]

# Things in the world you can hit.
const OBJECTS := {
	"tree": {"name": "Tree", "tool": "axe", "tier": 0, "hp": 5.0, "drops": {"wood": [2, 3]}},
	"old_tree": {"name": "Old Oak", "tool": "axe", "tier": 1, "hp": 10.0, "drops": {"wood": [6, 8]}},
	"boulder": {"name": "Boulder", "tool": "pickaxe", "tier": 0, "hp": 4.0, "drops": {"rock": [2, 3]}},
}

# Things you can build at home (left click to place, right click to pick back up).
const BUILDABLES := {
	"forge": {"name": "Forge", "size": Vector2i(2, 2), "cost": {"rock": 20}},
	"chair": {"name": "Chair", "size": Vector2i(1, 1), "cost": {"wood": 4}},
	"table": {"name": "Table", "size": Vector2i(2, 1), "cost": {"wood": 6}},
	"bookshelf": {"name": "Bookshelf", "size": Vector2i(2, 1), "cost": {"wood": 10}},
	"planter": {"name": "Planter", "size": Vector2i(1, 1), "cost": {"wood": 3, "rock": 2}},
}
const BUILD_ORDER := ["forge", "chair", "table", "bookshelf", "planter"]

const ENTITY_SIZES := {
	"door": Vector2i(2, 1),
	"bed": Vector2i(2, 3),
	"workbench": Vector2i(2, 1),
}
const NON_SOLID := ["ladder_down", "ladder_up"]

# Press E near these. The text is shown as the hint.
const INTERACTIONS := {
	"door": "Leave the house",
	"forge": "Use the forge",
	"workbench": "Use the workbench",
	"bed": "Bed",
	"ladder_down": "Climb down deeper",
	"ladder_up": "Climb out and go home (ends the day)",
	"exit_sign": "Walk back home (ends the day)",
}

const FORGE_LIGHT_COST := {"coal": 1}
const HANDLE_RECIPE := {"wood": 2}
const SMELTING := [
	{"input": "copper_ore", "amount": 2, "output": "copper_bar"},
	{"input": "iron_ore", "amount": 2, "output": "iron_bar"},
	{"input": "silver_ore", "amount": 2, "output": "silver_bar"},
	{"input": "gold_ore", "amount": 2, "output": "gold_bar"},
]


static func entity_size(kind: String) -> Vector2i:
	if BUILDABLES.has(kind):
		return BUILDABLES[kind]["size"]
	return ENTITY_SIZES.get(kind, Vector2i.ONE)


static func mine_floor_weights(depth: int) -> Dictionary:
	return MINE_FLOORS[mini(depth, MINE_FLOORS.size() - 1)]


static func pick_weighted(weights: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return weights.keys()[0]


## Why this tool can't hit that thing, or "" when it can.
static func tool_problem(target: Dictionary, tool: Dictionary) -> String:
	if target.is_empty() or tool.is_empty():
		return ""
	if tool["kind"] != target["tool"]:
		return "You need %s for that." % ("an axe" if target["tool"] == "axe" else "a pickaxe")
	if int(tool["tier"]) < int(target["tier"]):
		return "Your %s is too weak. You need a %s %s." % [
			tool["name"], TIER_NAMES[int(target["tier"])].to_lower(), target["tool"]]
	return ""


static func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for id in cost:
		parts.append("%d %s" % [cost[id], String(ITEMS[id]["name"]).to_lower()])
	return ", ".join(parts)
