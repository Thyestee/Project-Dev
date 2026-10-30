extends RefCounted
## Static game content: block types, ores, mine levels, upgrades and relics.

const AIR := 0
const STONE := 1
const COAL := 2
const COPPER := 3
const IRON := 4
const SILVER := 5
const GOLD := 6
const RUBY := 7
const EMERALD := 8
const MYTHRIL := 9
const RELIC := 10
const BEDROCK := 11

const ORE_ORDER := [COAL, COPPER, IRON, SILVER, GOLD, RUBY, EMERALD, MYTHRIL]
const GEMS := [RUBY, EMERALD, MYTHRIL]

const BLOCKS := {
	STONE: {"name": "Stone", "color": Color(0.5, 0.5, 0.5), "hardness": 1.0, "value": 0},
	COAL: {"name": "Coal", "color": Color(0.09, 0.09, 0.1), "hardness": 1.2, "value": 2},
	COPPER: {"name": "Copper", "color": Color(0.88, 0.48, 0.22), "hardness": 1.6, "value": 5},
	IRON: {"name": "Iron", "color": Color(0.8, 0.68, 0.6), "hardness": 2.2, "value": 12},
	SILVER: {"name": "Silver", "color": Color(0.86, 0.9, 0.95), "hardness": 3.0, "value": 25},
	GOLD: {"name": "Gold", "color": Color(1.0, 0.82, 0.2), "hardness": 4.0, "value": 50},
	RUBY: {"name": "Ruby", "color": Color(0.92, 0.12, 0.26), "hardness": 5.5, "value": 110},
	EMERALD: {"name": "Emerald", "color": Color(0.15, 0.86, 0.46), "hardness": 7.0, "value": 180},
	MYTHRIL: {"name": "Mythril", "color": Color(0.35, 0.9, 1.0), "hardness": 10.0, "value": 400},
	RELIC: {"name": "Relic", "color": Color(1.0, 0.9, 0.5), "hardness": 2.0, "value": 0},
}

# Each level is a floor of the mine. "weights" are the odds of each block when the
# floor (re)grows; "rock" tints the stone so every floor looks different.
const LEVELS := [
	{"name": "Shallow Tunnels", "cost": 0, "rock": Color(0.47, 0.37, 0.28), "relic_chance": 0.014,
		"weights": {STONE: 70, COAL: 18, COPPER: 10, IRON: 2}},
	{"name": "Copper Veins", "cost": 150, "rock": Color(0.44, 0.33, 0.29), "relic_chance": 0.014,
		"weights": {STONE: 62, COAL: 14, COPPER: 16, IRON: 8}},
	{"name": "Iron Depths", "cost": 600, "rock": Color(0.38, 0.36, 0.35), "relic_chance": 0.013,
		"weights": {STONE: 58, COAL: 8, COPPER: 10, IRON: 16, SILVER: 6}},
	{"name": "Silver Hollow", "cost": 1800, "rock": Color(0.33, 0.34, 0.41), "relic_chance": 0.013,
		"weights": {STONE: 55, COPPER: 6, IRON: 14, SILVER: 14, GOLD: 5}},
	{"name": "Golden Halls", "cost": 5000, "rock": Color(0.41, 0.33, 0.21), "relic_chance": 0.012,
		"weights": {STONE: 52, IRON: 10, SILVER: 14, GOLD: 14, RUBY: 4}},
	{"name": "Crimson Caverns", "cost": 12000, "rock": Color(0.4, 0.2, 0.18), "relic_chance": 0.012,
		"weights": {STONE: 52, SILVER: 10, GOLD: 14, RUBY: 12, EMERALD: 4}},
	{"name": "Emerald Grotto", "cost": 30000, "rock": Color(0.2, 0.31, 0.26), "relic_chance": 0.011,
		"weights": {STONE: 50, GOLD: 12, RUBY: 12, EMERALD: 12, MYTHRIL: 3}},
	{"name": "Mythril Core", "cost": 75000, "rock": Color(0.21, 0.21, 0.34), "relic_chance": 0.011,
		"weights": {STONE: 50, GOLD: 8, RUBY: 10, EMERALD: 12, MYTHRIL: 9}},
]

const PICKAXES := [
	{"name": "Wooden Pick", "power": 1.0, "cost": 0},
	{"name": "Stone Pick", "power": 1.7, "cost": 120},
	{"name": "Iron Pick", "power": 2.8, "cost": 500},
	{"name": "Steel Pick", "power": 4.5, "cost": 2000},
	{"name": "Diamond Pick", "power": 7.0, "cost": 8000},
	{"name": "Mythril Pick", "power": 11.0, "cost": 30000},
]

const BAGS := [
	{"name": "Pouch", "capacity": 10, "cost": 0},
	{"name": "Satchel", "capacity": 20, "cost": 100},
	{"name": "Backpack", "capacity": 35, "cost": 450},
	{"name": "Mule Pack", "capacity": 60, "cost": 1800},
	{"name": "Mine Cart", "capacity": 100, "cost": 7000},
	{"name": "Bottomless Bag", "capacity": 180, "cost": 25000},
]

# Rare finds hidden in sparkling relic blocks. Two per level; lower weight = rarer.
const COLLECTIBLES := [
	{"name": "Old Miner's Lamp", "level": 0, "weight": 3, "color": Color(1.0, 0.75, 0.3),
		"desc": "Still smells of lamp oil. Someone dug here long before you."},
	{"name": "Trilobite Fossil", "level": 0, "weight": 1, "color": Color(0.75, 0.68, 0.55),
		"desc": "A tiny armoured creature, frozen in stone for ages."},
	{"name": "Copper Coin", "level": 1, "weight": 3, "color": Color(0.85, 0.5, 0.25),
		"desc": "Stamped with a king nobody remembers."},
	{"name": "Lucky Horseshoe", "level": 1, "weight": 1, "color": Color(0.7, 0.72, 0.78),
		"desc": "From the pit ponies that once hauled ore here."},
	{"name": "Iron Locket", "level": 2, "weight": 3, "color": Color(0.6, 0.55, 0.52),
		"desc": "Rusted shut. Something rattles inside."},
	{"name": "Clockwork Beetle", "level": 2, "weight": 1, "color": Color(0.8, 0.6, 0.3),
		"desc": "Wind it up and it still scuttles a few steps."},
	{"name": "Silver Bell", "level": 3, "weight": 3, "color": Color(0.88, 0.9, 0.96),
		"desc": "Rings with a clear note that echoes down the shaft."},
	{"name": "Moonstone", "level": 3, "weight": 1, "color": Color(0.7, 0.8, 1.0),
		"desc": "Glows faintly, even in total darkness."},
	{"name": "Pharaoh's Ring", "level": 4, "weight": 3, "color": Color(1.0, 0.8, 0.25),
		"desc": "How did this end up so far from the desert?"},
	{"name": "Golden Idol", "level": 4, "weight": 1, "color": Color(1.0, 0.88, 0.4),
		"desc": "Heavy, grinning, and probably cursed."},
	{"name": "Fire Opal", "level": 5, "weight": 3, "color": Color(1.0, 0.4, 0.2),
		"desc": "Warm to the touch, like a coal that never cools."},
	{"name": "Dragon Tooth", "level": 5, "weight": 1, "color": Color(0.95, 0.92, 0.82),
		"desc": "Longer than your forearm. Best not to think about it."},
	{"name": "Jade Frog", "level": 6, "weight": 3, "color": Color(0.3, 0.8, 0.5),
		"desc": "A carved charm said to bring rain to dry valleys."},
	{"name": "Ancient Map", "level": 6, "weight": 1, "color": Color(0.85, 0.75, 0.55),
		"desc": "Shows tunnels even deeper than this mine goes."},
	{"name": "Star Fragment", "level": 7, "weight": 2, "color": Color(0.6, 0.95, 1.0),
		"desc": "Fell from the sky and kept falling, all the way down here."},
	{"name": "Heart of the Mountain", "level": 7, "weight": 1, "color": Color(1.0, 0.3, 0.5),
		"desc": "It beats, slowly. The whole mine seems to beat with it."},
]


static func pick_weighted(weights: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return int(k)
	return int(weights.keys()[0])
