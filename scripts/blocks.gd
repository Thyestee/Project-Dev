extends RefCounted
# Block ids and their properties. Every per-block table is indexed by block id.
# Everything from DIRT to BEDROCK is ground: one smooth surface that wears away a little with
# every blow. Ores and gems are ground too, flecked with what they hold. Everything after
# BEDROCK is built: crisp cubes, World.VOXEL metres on a side.

const AIR := 0
const DIRT := 1
const SAND := 2
const CLAY := 3
const GRAVEL := 4
const STONE := 5
const SLATE := 6
const DEEPROCK := 7
const COAL := 8           # 8 to 15: ores and gems, from the shallowest to the deepest
const COPPER_ORE := 9
const IRON_ORE := 10
const SILVER_ORE := 11
const AMETHYST := 12
const GOLD_ORE := 13
const RUBY := 14
const DIAMOND := 15
const BEDROCK := 16
const RELIC := 17
const CHEST := 18
const CHEST_TRIM := 19
const PLANK := 20
const WALL := 21
const BEAM := 22
const BRICK := 23
const WINDOW := 24
const LANTERN := 25
const WORKBENCH := 26
const IRON := 27
const RUG := 28
const RUG_TRIM := 29
const BLANKET := 30
const PILLOW := 31
const BOOK_RED := 32
const BOOK_GREEN := 33
const BOOK_BLUE := 34
const FIRE := 35
const COBBLE := 36
const PANEL := 37
const WALLPAPER := 38
const GOLD := 39
const LEAF := 40
const POT := 41
const TROPHY := 42        # 42 to 46: one colour per treasure rarity
const PLANK_DARK := 47
const VAULT_BRICK := 48
const VAULT_MOSS := 49
const VAULT_FLOOR := 50
const VAULT_TILE := 51
const VAULT_PILLAR := 52
const TORCH := 53
const BONE := 54
const WEB := 55
const BANNER := 56
const LOOT_CHEST := 57
const LOOT_TRIM := 58     # 58 to 61: uncommon, rare, epic and legendary loot chests
const LOOT_LOCK := 62
const LOOT_EMPTY := 63    # the trim of a chest you've emptied
const STEEL := 64
const DARK_IRON := 65
const STUMP := 66
const STRAW := 67
const SACK := 68
const PARCHMENT := 69
const CRATE := 70
const CRATE_BAND := 71
const URN := 72
const EMBER := 73

# name, colour, pick tier that can dig it (-1: nothing can), seconds per swing, glow, how much
# the shade varies from cube to cube (or triangle to triangle), and the sound a pickaxe makes
# on it (see Sfx).
const DEFS := [
	["Air", Color(0, 0, 0), -1, 0.0, 0.0, 0.0, ""],
	["Dirt", Color(0.45, 0.31, 0.2), 0, 0.32, 0.0, 0.22, "soft"],
	["Sand", Color(0.8, 0.7, 0.47), 0, 0.28, 0.0, 0.16, "sand"],
	["Clay", Color(0.62, 0.45, 0.36), 0, 0.42, 0.0, 0.2, "soft"],
	["Gravel", Color(0.5, 0.48, 0.45), 0, 0.38, 0.0, 0.3, "gravel"],
	["Stone", Color(0.5, 0.5, 0.52), 1, 0.5, 0.0, 0.22, "stone"],
	["Slate", Color(0.3, 0.33, 0.4), 2, 0.6, 0.0, 0.2, "slate"],
	["Deeprock", Color(0.24, 0.18, 0.28), 3, 0.75, 0.0, 0.22, "hard"],
	["Coal", Color(0.15, 0.14, 0.14), 0, 0.42, 0.0, 0.3, "coal"],
	["Copper ore", Color(0.45, 0.36, 0.29), 0, 0.48, 0.05, 0.3, "ore"],
	["Iron ore", Color(0.48, 0.39, 0.35), 0, 0.52, 0.0, 0.3, "ore"],
	["Silver ore", Color(0.43, 0.44, 0.48), 1, 0.58, 0.18, 0.3, "ore"],
	["Amethyst", Color(0.37, 0.31, 0.43), 1, 0.62, 0.3, 0.3, "gem"],
	["Gold ore", Color(0.41, 0.37, 0.32), 2, 0.64, 0.32, 0.3, "ore"],
	["Ruby", Color(0.36, 0.27, 0.3), 2, 0.72, 0.35, 0.3, "gem"],
	["Diamond", Color(0.3, 0.29, 0.36), 2, 0.8, 0.45, 0.3, "gem"],
	["Bedrock", Color(0.13, 0.12, 0.12), -1, 0.0, 0.0, 0.15, "bedrock"],
	["Glinting soil", Color(1.0, 0.78, 0.25), 0, 0.4, 0.6, 0.12, "treasure"],
	["Buried chest", Color(0.45, 0.28, 0.14), 0, 0.4, 0.12, 0.12, "treasure"],
	["Buried chest", Color(1.0, 0.8, 0.3), 0, 0.4, 0.6, 0.08, "treasure"],
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
	["Ancient brick", Color(0.42, 0.4, 0.36), 0, 0.7, 0.0, 0.2, "brick"],
	["Mossy brick", Color(0.33, 0.42, 0.27), 0, 0.7, 0.0, 0.25, "brick"],
	["Floor tile", Color(0.34, 0.31, 0.29), 0, 0.7, 0.0, 0.12, "brick"],
	["Floor tile", Color(0.47, 0.43, 0.37), 0, 0.7, 0.0, 0.12, "brick"],
	["Pillar", Color(0.52, 0.49, 0.44), 0, 0.7, 0.0, 0.1, "brick"],
	["Torch", Color(1.0, 0.62, 0.25), 0, 0.2, 1.4, 0.15, "wood"],
	["Bones", Color(0.86, 0.83, 0.74), 0, 0.2, 0.0, 0.12, "bone"],
	["Cobweb", Color(0.78, 0.78, 0.8), 0, 0.15, 0.0, 0.05, "cloth"],
	["Banner", Color(0.5, 0.1, 0.1), 0, 0.2, 0.0, 0.08, "cloth"],
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
	["Urn", Color(0.55, 0.35, 0.22), 0, 0.2, 0.0, 0.12, "brick"],
	["Embers", Color(0.85, 0.25, 0.08), -1, 0.0, 1.1, 0.3, "soft"],
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
}

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
	return b >= COAL and b <= DIAMOND


static func is_treasure(b: int) -> bool:
	return b == RELIC or b == CHEST or b == CHEST_TRIM


# Ground you can dig: everything but bedrock.
static func is_natural(b: int) -> bool:
	return b >= DIRT and b < BEDROCK


# Hidden-room masonry: breaking any of it is how you get in.
static func is_vault(b: int) -> bool:
	return b >= VAULT_BRICK and b <= BANNER or b == URN


static func is_loot_chest(b: int) -> bool:
	return b >= LOOT_CHEST and b <= LOOT_EMPTY


# Whether a pick (or a blast) of this tier breaks the block. Treasure comes out whole instead.
static func diggable(b: int, tier: int) -> bool:
	var t := TIER[b]
	return t >= 0 and t <= tier and not is_treasure(b)
