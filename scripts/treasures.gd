extends RefCounted
# The lost treasures buried in the ground and hidden away in old rooms. They're rare, they only
# turn up deep down, and the rarer ones only further down still. Depths are in metres below the
# room floor; a treasure found deeper is worth more (see value_at).

const Blocks := preload("res://scripts/blocks.gd")

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [Color(0.85, 0.85, 0.85), Color(0.5, 0.9, 0.45), Color(0.45, 0.7, 1.0), Color(0.8, 0.55, 1.0), Color(1.0, 0.8, 0.25)]

# Rare and better treasures sit in buried chests; the rest glint in the soil.
const LIST := [
	{"name": "Old Copper Coin", "rarity": 0, "value": 90, "weight": 30.0, "depth": [18, 400], "chest": false,
		"text": "Worn smooth by the soil. Someone lost it on a long walk."},
	{"name": "Painted Pottery Shard", "rarity": 0, "value": 110, "weight": 26.0, "depth": [18, 500], "chest": false,
		"text": "A curve of blue glaze from a much bigger jug."},
	{"name": "Flint Arrowhead", "rarity": 0, "value": 130, "weight": 20.0, "depth": [20, 600], "chest": false,
		"text": "Chipped by hand and still sharp after all this time."},
	{"name": "Bronze Belt Buckle", "rarity": 1, "value": 220, "weight": 16.0, "depth": [30, 1000], "chest": false,
		"text": "Green with age, with a running horse on the front."},
	{"name": "Silver Ring", "rarity": 1, "value": 320, "weight": 12.0, "depth": [40, 1500], "chest": false,
		"text": "There's an inscription inside, too worn to read."},
	{"name": "Brass Pocket Watch", "rarity": 1, "value": 450, "weight": 9.0, "depth": [60, 2000], "chest": false,
		"text": "Stopped at a quarter past three, forever."},
	{"name": "Jade Figurine", "rarity": 2, "value": 700, "weight": 7.0, "depth": [100, 3000], "chest": true,
		"text": "A small carved fox, cool to the touch."},
	{"name": "Ceremonial Dagger", "rarity": 2, "value": 900, "weight": 5.0, "depth": [150, 4000], "chest": true,
		"text": "Far too ornate to have ever seen a fight."},
	{"name": "Pouch of Gold Coins", "rarity": 2, "value": 1200, "weight": 4.0, "depth": [200, 6000], "chest": true,
		"text": "The leather crumbles away. The coins don't."},
	{"name": "Jeweled Brooch", "rarity": 3, "value": 1800, "weight": 3.0, "depth": [400, 10000], "chest": true,
		"text": "Three red stones set in a silver flower."},
	{"name": "Golden Idol", "rarity": 3, "value": 2600, "weight": 2.0, "depth": [700, 10000], "chest": true,
		"text": "Heavy, grinning, and strangely warm."},
	{"name": "Crown of the Sunken King", "rarity": 4, "value": 6000, "weight": 0.4, "depth": [1500, 10000], "chest": true,
		"text": "So the old story was true. Hardly anyone has ever held one."},
]
const CROWN := 11


# A treasure that belongs at this depth, or -1 if none does.
static func pick(rng: RandomNumberGenerator, depth: float) -> int:
	var total := 0.0
	for t in LIST:
		if depth >= float(t["depth"][0]) and depth <= float(t["depth"][1]):
			total += float(t["weight"])
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	for i in LIST.size():
		var t: Dictionary = LIST[i]
		if depth >= float(t["depth"][0]) and depth <= float(t["depth"][1]):
			roll -= float(t["weight"])
			if roll < 0.0:
				return i
	return 0


# What a treasure found at this depth sells for: a little more for every band of rock above it.
static func value_at(t: int, depth: float) -> int:
	return roundi(int(LIST[t]["value"]) * pow(1.3, Blocks.level(depth)))
