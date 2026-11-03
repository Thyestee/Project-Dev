extends RefCounted
# Block ids and their properties. Every per-block table is indexed by block id.
# Everything from DIRT to BEDROCK is ground: one smooth surface that wears away a little with
# every blow. Ores and gems are ground too, flecked with what they hold. Everything after
# BEDROCK is built: crisp cubes, World.VOXEL metres on a side.
#
# The ground comes in bands, each harder than the last, down to the bedrock 10 km below your
# house (see BANDS): every band needs a better pickaxe.

const AIR := 0
const DIRT := 1
const SAND := 2
const CLAY := 3
const GRAVEL := 4
const STONE := 5
const SLATE := 6
const DEEPROCK := 7
const BASALT := 8
const OBSIDIAN := 9
const MAGMAROCK := 10
const VOIDSTONE := 11
const COAL := 12          # 12 to 24: ores and gems, from the shallowest to the deepest
const COPPER_ORE := 13
const IRON_ORE := 14
const SILVER_ORE := 15
const AMETHYST := 16
const GOLD_ORE := 17
const RUBY := 18
const DIAMOND := 19
const MITHRIL_ORE := 20
const SAPPHIRE := 21
const ADAMANT_ORE := 22
const EMERALD := 23
const STARMETAL_ORE := 24
const BEDROCK := 25
const RELIC := 26
const CHEST := 27
const CHEST_TRIM := 28
const PLANK := 29
const WALL := 30
const BEAM := 31
const BRICK := 32
const WINDOW := 33
const LANTERN := 34
const WORKBENCH := 35
const IRON := 36
const RUG := 37
const RUG_TRIM := 38
const BLANKET := 39
const PILLOW := 40
const BOOK_RED := 41
const BOOK_GREEN := 42
const BOOK_BLUE := 43
const FIRE := 44
const COBBLE := 45
const PANEL := 46
const WALLPAPER := 47
const GOLD := 48
const LEAF := 49
const POT := 50
const TROPHY := 51        # 51 to 55: one colour per treasure rarity
const PLANK_DARK := 56
const VAULT_BRICK := 57
const VAULT_MOSS := 58
const VAULT_FLOOR := 59
const VAULT_TILE := 60
const VAULT_PILLAR := 61
const TORCH := 62
const BONE := 63
const WEB := 64
const BANNER := 65
const LOOT_CHEST := 66
const LOOT_TRIM := 67     # 67 to 70: uncommon, rare, epic and legendary loot chests
const LOOT_LOCK := 71
const LOOT_EMPTY := 72    # the trim of a chest you've emptied
const STEEL := 73
const DARK_IRON := 74
const STUMP := 75
const STRAW := 76
const SACK := 77
const PARCHMENT := 78
const CRATE := 79
const CRATE_BAND := 80
const URN := 81
const EMBER := 82
const TRIAL_STONE := 83   # a trial's walls, floor and platforms: nothing digs through them
const TRIAL_TRIM := 84
const TRIAL_GLOW := 85    # the glowing marks on a trial's platforms
const TRAP_PLATE := 86    # a pressure plate in a treasure room's floor
const DART_SLIT := 87     # where a dart trap's darts fly out
const ROPE := 88          # the rope lift by your door

# name, colour, pick tier that can dig it (-1: nothing can; see Items.MATERIALS), seconds per
# swing, glow, how much the shade varies from cube to cube (or triangle to triangle), and the
# sound a pickaxe makes on it (see Sfx).
const DEFS := [
	["Air", Color(0, 0, 0), -1, 0.0, 0.0, 0.0, ""],
	["Dirt", Color(0.45, 0.31, 0.2), 1, 0.32, 0.0, 0.22, "soft"],
	["Sand", Color(0.8, 0.7, 0.47), 1, 0.28, 0.0, 0.16, "sand"],
	["Clay", Color(0.62, 0.45, 0.36), 1, 0.42, 0.0, 0.2, "soft"],
	["Gravel", Color(0.5, 0.48, 0.45), 1, 0.38, 0.0, 0.3, "gravel"],
	["Stone", Color(0.5, 0.5, 0.52), 2, 0.5, 0.0, 0.22, "stone"],
	["Slate", Color(0.3, 0.33, 0.4), 3, 0.6, 0.0, 0.2, "slate"],
	["Deeprock", Color(0.24, 0.18, 0.28), 4, 0.75, 0.0, 0.22, "hard"],
	["Basalt", Color(0.2, 0.22, 0.25), 5, 0.8, 0.0, 0.2, "hard"],
	["Obsidian", Color(0.13, 0.1, 0.17), 6, 0.85, 0.06, 0.18, "glass"],
	["Magmarock", Color(0.34, 0.13, 0.08), 7, 0.9, 0.14, 0.28, "hard"],
	["Voidstone", Color(0.09, 0.09, 0.16), 8, 0.95, 0.08, 0.2, "hard"],
	["Coal", Color(0.15, 0.14, 0.14), 1, 0.42, 0.0, 0.3, "coal"],
	["Copper ore", Color(0.45, 0.36, 0.29), 1, 0.48, 0.05, 0.3, "ore"],
	["Iron ore", Color(0.48, 0.39, 0.35), 1, 0.52, 0.0, 0.3, "ore"],
	["Silver ore", Color(0.43, 0.44, 0.48), 2, 0.58, 0.18, 0.3, "ore"],
	["Amethyst", Color(0.37, 0.31, 0.43), 2, 0.62, 0.3, 0.3, "gem"],
	["Gold ore", Color(0.41, 0.37, 0.32), 3, 0.64, 0.32, 0.3, "ore"],
	["Ruby", Color(0.36, 0.27, 0.3), 3, 0.72, 0.35, 0.3, "gem"],
	["Diamond", Color(0.3, 0.29, 0.36), 4, 0.8, 0.45, 0.3, "gem"],
	["Mithril ore", Color(0.25, 0.27, 0.31), 5, 0.82, 0.4, 0.3, "ore"],
	["Sapphire", Color(0.2, 0.21, 0.3), 5, 0.85, 0.45, 0.3, "gem"],
	["Adamant ore", Color(0.2, 0.14, 0.18), 6, 0.88, 0.4, 0.3, "ore"],
	["Emerald", Color(0.14, 0.17, 0.16), 6, 0.9, 0.45, 0.3, "gem"],
	["Starmetal ore", Color(0.16, 0.15, 0.2), 7, 0.95, 0.6, 0.3, "ore"],
	["Bedrock", Color(0.13, 0.12, 0.12), -1, 0.0, 0.0, 0.15, "bedrock"],
	["Glinting soil", Color(1.0, 0.78, 0.25), 1, 0.4, 0.6, 0.12, "treasure"],
	["Buried chest", Color(0.45, 0.28, 0.14), 1, 0.4, 0.12, 0.12, "treasure"],
	["Buried chest", Color(1.0, 0.8, 0.3), 1, 0.4, 0.6, 0.08, "treasure"],
	["Floorboards", Color(0.64, 0.46, 0.29), -1, 0.0, 0.0, 0.1, "wood"],
	["Wooden wall", Color(0.52, 0.38, 0.25), -1, 0.0, 0.0, 0.12, "wood"],
	["Beam", Color(0.33, 0.22, 0.14), -1, 0.0, 0.0, 0.08, "wood"],
	["Brick", Color(0.56, 0.36, 0.3), -1, 0.0, 0.0, 0.16, "brick"],
	["Window", Color(0.72, 0.86, 1.0), -1, 0.0, 0.85, 0.04, "glass"],
	["Lantern", Color(1.0, 0.82, 0.45), -1, 0.0, 1.2, 0.04, "glass"],
	["Workbench", Color(0.72, 0.56, 0.36), -1, 0.0, 0.0, 0.08, "wood"],
	["Iron", Color(0.3, 0.31, 0.33), -1, 0.0, 0.0, 0.06, "metal"],
	["Rug", Color(0.62, 0.16, 0.14), -1, 0.0, 0.0, 0.08, "cloth"],
	["Rug", Color(0.9, 0.7, 0.3), -1, 0.0, 0.0, 0.06, "cloth"],
	["Bed", Color(0.22, 0.36, 0.62), -1, 0.0, 0.0, 0.06, "cloth"],
	["Pillow", Color(0.92, 0.9, 0.85), -1, 0.0, 0.0, 0.04, "cloth"],
	["Book", Color(0.6, 0.15, 0.12), -1, 0.0, 0.0, 0.12, "cloth"],
	["Book", Color(0.18, 0.42, 0.22), -1, 0.0, 0.0, 0.12, "cloth"],
	["Book", Color(0.18, 0.25, 0.55), -1, 0.0, 0.0, 0.12, "cloth"],
	["Fire", Color(1.0, 0.55, 0.15), -1, 0.0, 1.5, 0.2, "soft"],
	["Fireplace", Color(0.46, 0.45, 0.43), -1, 0.0, 0.0, 0.2, "brick"],
	["Panelling", Color(0.48, 0.3, 0.18), -1, 0.0, 0.0, 0.06, "wood"],
	["Wallpaper", Color(0.4, 0.5, 0.38), -1, 0.0, 0.0, 0.05, "wood"],
	["Gold", Color(1.0, 0.8, 0.3), -1, 0.0, 0.3, 0.08, "metal"],
	["Plant", Color(0.3, 0.58, 0.25), -1, 0.0, 0.0, 0.2, "cloth"],
	["Pot", Color(0.72, 0.38, 0.22), -1, 0.0, 0.0, 0.1, "brick"],
	["Trophy", Color(0.85, 0.85, 0.85), -1, 0.0, 0.45, 0.05, "metal"],
	["Trophy", Color(0.5, 0.9, 0.45), -1, 0.0, 0.45, 0.05, "metal"],
	["Trophy", Color(0.45, 0.7, 1.0), -1, 0.0, 0.45, 0.05, "metal"],
	["Trophy", Color(0.8, 0.55, 1.0), -1, 0.0, 0.45, 0.05, "metal"],
	["Trophy", Color(1.0, 0.8, 0.25), -1, 0.0, 0.45, 0.05, "metal"],
	["Floorboards", Color(0.52, 0.36, 0.22), -1, 0.0, 0.0, 0.1, "wood"],
	["Ancient brick", Color(0.42, 0.4, 0.36), 1, 0.7, 0.0, 0.2, "brick"],
	["Mossy brick", Color(0.33, 0.42, 0.27), 1, 0.7, 0.0, 0.25, "brick"],
	["Floor tile", Color(0.34, 0.31, 0.29), 1, 0.7, 0.0, 0.12, "brick"],
	["Floor tile", Color(0.47, 0.43, 0.37), 1, 0.7, 0.0, 0.12, "brick"],
	["Pillar", Color(0.52, 0.49, 0.44), 1, 0.7, 0.0, 0.1, "brick"],
	["Torch", Color(1.0, 0.62, 0.25), 1, 0.2, 1.4, 0.15, "wood"],
	["Bones", Color(0.86, 0.83, 0.74), 1, 0.2, 0.0, 0.12, "bone"],
	["Cobweb", Color(0.78, 0.78, 0.8), 1, 0.15, 0.0, 0.05, "cloth"],
	["Banner", Color(0.5, 0.1, 0.1), 1, 0.2, 0.0, 0.08, "cloth"],
	["Old chest", Color(0.36, 0.22, 0.12), -1, 0.0, 0.0, 0.1, "wood"],
	["Old chest", Color(0.4, 0.9, 0.4), -1, 0.0, 0.8, 0.04, "wood"],
	["Old chest", Color(0.4, 0.65, 1.0), -1, 0.0, 0.8, 0.04, "wood"],
	["Old chest", Color(0.75, 0.45, 1.0), -1, 0.0, 0.9, 0.04, "wood"],
	["Old chest", Color(1.0, 0.62, 0.12), -1, 0.0, 1.0, 0.04, "wood"],
	["Old chest", Color(1.0, 0.82, 0.35), -1, 0.0, 0.3, 0.04, "metal"],
	["Old chest", Color(0.34, 0.32, 0.29), -1, 0.0, 0.0, 0.06, "wood"],
	["Steel", Color(0.62, 0.65, 0.7), -1, 0.0, 0.0, 0.05, "metal"],
	["Iron", Color(0.22, 0.22, 0.24), -1, 0.0, 0.0, 0.06, "metal"],
	["Stump", Color(0.42, 0.29, 0.17), -1, 0.0, 0.0, 0.12, "wood"],
	["Straw", Color(0.85, 0.72, 0.38), -1, 0.0, 0.0, 0.18, "cloth"],
	["Sacking", Color(0.66, 0.56, 0.4), -1, 0.0, 0.0, 0.1, "cloth"],
	["Map", Color(0.88, 0.8, 0.6), -1, 0.0, 0.0, 0.06, "cloth"],
	["Crate", Color(0.58, 0.4, 0.22), -1, 0.0, 0.0, 0.1, "wood"],
	["Iron band", Color(0.3, 0.3, 0.32), -1, 0.0, 0.0, 0.05, "metal"],
	["Urn", Color(0.55, 0.35, 0.22), 1, 0.2, 0.0, 0.12, "brick"],
	["Embers", Color(0.85, 0.25, 0.08), -1, 0.0, 1.1, 0.3, "soft"],
	["Trial stone", Color(0.42, 0.44, 0.5), -1, 0.0, 0.0, 0.08, "bedrock"],
	["Trial stone", Color(0.82, 0.66, 0.34), -1, 0.0, 0.35, 0.05, "metal"],
	["Trial stone", Color(0.4, 0.85, 1.0), -1, 0.0, 0.9, 0.03, "bedrock"],
	["Floor tile", Color(0.41, 0.38, 0.33), 1, 0.7, 0.0, 0.04, "brick"],
	["Dart slit", Color(0.12, 0.11, 0.1), 1, 0.7, 0.0, 0.05, "brick"],
	["Rope", Color(0.72, 0.6, 0.38), -1, 0.0, 0.0, 0.12, "cloth"],
]

# The flecks of metal or crystal that glint in each ore and gem.
const FLECKS := {
	COAL: Color(0.33, 0.34, 0.39),
	COPPER_ORE: Color(0.86, 0.47, 0.23),
	IRON_ORE: Color(0.7, 0.36, 0.22),
	SILVER_ORE: Color(0.84, 0.87, 0.94),
	AMETHYST: Color(0.64, 0.38, 0.92),
	GOLD_ORE: Color(0.96, 0.75, 0.24),
	RUBY: Color(0.88, 0.14, 0.22),
	DIAMOND: Color(0.66, 0.93, 0.98),
	MITHRIL_ORE: Color(0.6, 0.84, 1.0),
	SAPPHIRE: Color(0.2, 0.4, 1.0),
	ADAMANT_ORE: Color(0.86, 0.18, 0.46),
	EMERALD: Color(0.2, 0.88, 0.42),
	STARMETAL_ORE: Color(1.0, 0.95, 0.72),
}

# Where each band of rock starts, in metres below your house floor, and the rock it's made of.
# The last number is the bedrock at the bottom of the world.
const BANDS := [0.0, 13.0, 40.0, 110.0, 280.0, 700.0, 1800.0, 4500.0, 10000.0]
const BAND_ROCK := [DIRT, STONE, SLATE, DEEPROCK, BASALT, OBSIDIAN, MAGMAROCK, VOIDSTONE]

static var NAMES: Array = []
static var COLORS: Array = []
static var TIER := PackedInt32Array()
static var DIG_TIME := PackedFloat32Array()
static var GLOW := PackedFloat32Array()
static var JITTER := PackedFloat32Array()
static var SOUND: Array[String] = []


static func _static_init() -> void:
	for row: Array in DEFS:
		NAMES.append(row[0])
		COLORS.append(row[1])
		TIER.append(row[2])
		DIG_TIME.append(row[3])
		GLOW.append(row[4])
		JITTER.append(row[5])
		SOUND.append(row[6])


static func is_ground(b: int) -> bool:
	return b >= DIRT and b <= BEDROCK


static func is_ore(b: int) -> bool:
	return b >= COAL and b <= STARMETAL_ORE


static func is_treasure(b: int) -> bool:
	return b == RELIC or b == CHEST or b == CHEST_TRIM


# Ground you can dig: everything but bedrock.
static func is_natural(b: int) -> bool:
	return b >= DIRT and b < BEDROCK


# Hidden-room masonry: breaking any of it is how you get in.
static func is_vault(b: int) -> bool:
	return b >= VAULT_BRICK and b <= BANNER or b == URN or b == TRAP_PLATE or b == DART_SLIT


static func is_trial(b: int) -> bool:
	return b >= TRIAL_STONE and b <= TRIAL_GLOW


static func is_loot_chest(b: int) -> bool:
	return b >= LOOT_CHEST and b <= LOOT_EMPTY


# Whether a pick (or a blast) of this tier breaks the block. Treasure comes out whole instead.
static func diggable(b: int, tier: int) -> bool:
	var t := TIER[b]
	return t >= 0 and t <= tier and not is_treasure(b)


# How deep down you are, as a number from 0 (just under your house) to 8 (the bottom): which band
# of rock you're in, and how far through it. Guards, loot and treasure all grow with it.
static func level(depth: float) -> float:
	if depth <= 0.0:
		return 0.0
	for k in range(BANDS.size() - 1):
		if depth < BANDS[k + 1]:
			return k + (depth - BANDS[k]) / (BANDS[k + 1] - BANDS[k])
	return float(BANDS.size() - 1)


# The band of rock at a depth (0 to 7).
static func band(depth: float) -> int:
	return clampi(floori(level(depth)), 0, BAND_ROCK.size() - 1)
