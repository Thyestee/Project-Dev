extends RefCounted
# The lost treasures buried at every dig site. Depths are in metres below the room floor.

const PER_WORLD := 45
const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [Color(0.85, 0.85, 0.85), Color(0.5, 0.9, 0.45), Color(0.45, 0.7, 1.0), Color(0.8, 0.55, 1.0), Color(1.0, 0.8, 0.25)]

# Rare and better treasures sit in buried chests; the rest glint in the soil.
const LIST := [
	{"name": "Old Copper Coin", "rarity": 0, "value": 10, "weight": 30.0, "depth": [1, 8], "chest": false,
		"text": "Worn smooth by the soil. Someone lost it on a long walk."},
	{"name": "Painted Pottery Shard", "rarity": 0, "value": 15, "weight": 26.0, "depth": [2, 10], "chest": false,
		"text": "A curve of blue glaze from a much bigger jug."},
	{"name": "Flint Arrowhead", "rarity": 0, "value": 20, "weight": 20.0, "depth": [2, 12], "chest": false,
		"text": "Chipped by hand and still sharp after all this time."},
	{"name": "Bronze Belt Buckle", "rarity": 1, "value": 35, "weight": 16.0, "depth": [4, 14], "chest": false,
		"text": "Green with age, with a running horse on the front."},
	{"name": "Silver Ring", "rarity": 1, "value": 60, "weight": 12.0, "depth": [6, 18], "chest": false,
		"text": "There's an inscription inside, too worn to read."},
	{"name": "Brass Pocket Watch", "rarity": 1, "value": 90, "weight": 9.0, "depth": [8, 22], "chest": false,
		"text": "Stopped at a quarter past three, forever."},
	{"name": "Jade Figurine", "rarity": 2, "value": 150, "weight": 7.0, "depth": [12, 26], "chest": true,
		"text": "A small carved fox, cool to the touch."},
	{"name": "Ceremonial Dagger", "rarity": 2, "value": 220, "weight": 5.0, "depth": [14, 30], "chest": true,
		"text": "Far too ornate to have ever seen a fight."},
	{"name": "Pouch of Gold Coins", "rarity": 2, "value": 320, "weight": 4.0, "depth": [16, 32], "chest": true,
		"text": "The leather crumbles away. The coins don't."},
	{"name": "Jeweled Brooch", "rarity": 3, "value": 480, "weight": 3.0, "depth": [20, 36], "chest": true,
		"text": "Three red stones set in a silver flower."},
	{"name": "Golden Idol", "rarity": 3, "value": 800, "weight": 2.0, "depth": [24, 40], "chest": true,
		"text": "Heavy, grinning, and strangely warm."},
	{"name": "Crown of the Sunken King", "rarity": 4, "value": 2000, "weight": 0.0, "depth": [28, 44], "chest": true,
		"text": "So the old story was true. There is only one."},
]
# Every world hides exactly one crown.
const CROWN := 11


static func pick(rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for t in LIST:
		total += float(t["weight"])
	var roll := rng.randf() * total
	for i in LIST.size():
		roll -= float(LIST[i]["weight"])
		if roll < 0.0:
			return i
	return 0
