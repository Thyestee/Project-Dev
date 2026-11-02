extends RefCounted
# Block ids and their properties. Every per-block table is indexed by block id.
# Everything from DIRT to BEDROCK is ground: one smooth surface that wears away a little with
# every blow. Everything after BEDROCK is built: crisp cubes, World.VOXEL metres on a side.

const AIR := 0
const DIRT := 1
const SAND := 2
const CLAY := 3
const GRAVEL := 4
const STONE := 5
const SLATE := 6
const DEEPROCK := 7
const BEDROCK := 8
const RELIC := 9
const CHEST := 10
const CHEST_TRIM := 11
const PLANK := 12
const WALL := 13
const BEAM := 14
const BRICK := 15
const WINDOW := 16
const LANTERN := 17
const WORKBENCH := 18
const IRON := 19
const RUG := 20
const RUG_TRIM := 21
const BLANKET := 22
const PILLOW := 23
const BOOK_RED := 24
const BOOK_GREEN := 25
const BOOK_BLUE := 26
const FIRE := 27
const COBBLE := 28
const PANEL := 29
const WALLPAPER := 30
const GOLD := 31
const LEAF := 32
const POT := 33
const TROPHY := 34        # 34 to 38: one colour per treasure rarity
const PLANK_DARK := 39
const VAULT_BRICK := 40
const VAULT_MOSS := 41
const VAULT_FLOOR := 42
const VAULT_TILE := 43
const VAULT_PILLAR := 44
const TORCH := 45
const BONE := 46
const WEB := 47
const BANNER := 48
const LOOT_CHEST := 49
const LOOT_TRIM := 50     # 50 to 53: uncommon, rare, epic and legendary loot chests
const LOOT_LOCK := 54
const LOOT_EMPTY := 55    # the trim of a chest you've emptied
const STEEL := 56
const DARK_IRON := 57
const STUMP := 58
const STRAW := 59
const SACK := 60
const PARCHMENT := 61
const CRATE := 62
const CRATE_BAND := 63
const URN := 64

# name, colour, pick tier that can dig it (-1: nothing can), seconds per swing, glow, how much
# the shade varies from cube to cube.
const DEFS := [
	["Air", Color(0, 0, 0), -1, 0.0, 0.0, 0.0],
	["Dirt", Color(0.45, 0.31, 0.2), 0, 0.32, 0.0, 0.22],
	["Sand", Color(0.8, 0.7, 0.47), 0, 0.28, 0.0, 0.16],
	["Clay", Color(0.62, 0.45, 0.36), 0, 0.42, 0.0, 0.2],
	["Gravel", Color(0.5, 0.48, 0.45), 0, 0.38, 0.0, 0.3],
	["Stone", Color(0.5, 0.5, 0.52), 1, 0.5, 0.0, 0.22],
	["Slate", Color(0.3, 0.33, 0.4), 2, 0.6, 0.0, 0.2],
	["Deeprock", Color(0.24, 0.18, 0.28), 3, 0.75, 0.0, 0.22],
	["Bedrock", Color(0.13, 0.12, 0.12), -1, 0.0, 0.0, 0.15],
	["Glinting soil", Color(1.0, 0.78, 0.25), 0, 0.4, 0.6, 0.12],
	["Buried chest", Color(0.45, 0.28, 0.14), 0, 0.4, 0.12, 0.12],
	["Buried chest", Color(1.0, 0.8, 0.3), 0, 0.4, 0.6, 0.08],
	["Floorboards", Color(0.64, 0.46, 0.29), -1, 0.0, 0.0, 0.1],
	["Wooden wall", Color(0.52, 0.38, 0.25), -1, 0.0, 0.0, 0.12],
	["Beam", Color(0.33, 0.22, 0.14), -1, 0.0, 0.0, 0.08],
	["Brick", Color(0.56, 0.36, 0.3), -1, 0.0, 0.0, 0.16],
	["Window", Color(0.72, 0.86, 1.0), -1, 0.0, 0.85, 0.04],
	["Lantern", Color(1.0, 0.82, 0.45), -1, 0.0, 1.2, 0.04],
	["Workbench", Color(0.72, 0.56, 0.36), -1, 0.0, 0.0, 0.08],
	["Iron", Color(0.3, 0.31, 0.33), -1, 0.0, 0.0, 0.06],
	["Rug", Color(0.62, 0.16, 0.14), -1, 0.0, 0.0, 0.08],
	["Rug", Color(0.9, 0.7, 0.3), -1, 0.0, 0.0, 0.06],
	["Bed", Color(0.22, 0.36, 0.62), -1, 0.0, 0.0, 0.06],
	["Pillow", Color(0.92, 0.9, 0.85), -1, 0.0, 0.0, 0.04],
	["Book", Color(0.6, 0.15, 0.12), -1, 0.0, 0.0, 0.12],
	["Book", Color(0.18, 0.42, 0.22), -1, 0.0, 0.0, 0.12],
	["Book", Color(0.18, 0.25, 0.55), -1, 0.0, 0.0, 0.12],
	["Fire", Color(1.0, 0.55, 0.15), -1, 0.0, 1.5, 0.2],
	["Fireplace", Color(0.46, 0.45, 0.43), -1, 0.0, 0.0, 0.2],
	["Panelling", Color(0.48, 0.3, 0.18), -1, 0.0, 0.0, 0.06],
	["Wallpaper", Color(0.4, 0.5, 0.38), -1, 0.0, 0.0, 0.05],
	["Gold", Color(1.0, 0.8, 0.3), -1, 0.0, 0.3, 0.08],
	["Plant", Color(0.3, 0.58, 0.25), -1, 0.0, 0.0, 0.2],
	["Pot", Color(0.72, 0.38, 0.22), -1, 0.0, 0.0, 0.1],
	["Trophy", Color(0.85, 0.85, 0.85), -1, 0.0, 0.45, 0.05],
	["Trophy", Color(0.5, 0.9, 0.45), -1, 0.0, 0.45, 0.05],
	["Trophy", Color(0.45, 0.7, 1.0), -1, 0.0, 0.45, 0.05],
	["Trophy", Color(0.8, 0.55, 1.0), -1, 0.0, 0.45, 0.05],
	["Trophy", Color(1.0, 0.8, 0.25), -1, 0.0, 0.45, 0.05],
	["Floorboards", Color(0.52, 0.36, 0.22), -1, 0.0, 0.0, 0.1],
	["Ancient brick", Color(0.42, 0.4, 0.36), 0, 0.7, 0.0, 0.2],
	["Mossy brick", Color(0.33, 0.42, 0.27), 0, 0.7, 0.0, 0.25],
	["Floor tile", Color(0.34, 0.31, 0.29), 0, 0.7, 0.0, 0.12],
	["Floor tile", Color(0.47, 0.43, 0.37), 0, 0.7, 0.0, 0.12],
	["Pillar", Color(0.52, 0.49, 0.44), 0, 0.7, 0.0, 0.1],
	["Torch", Color(1.0, 0.62, 0.25), 0, 0.2, 1.4, 0.15],
	["Bones", Color(0.86, 0.83, 0.74), 0, 0.2, 0.0, 0.12],
	["Cobweb", Color(0.78, 0.78, 0.8), 0, 0.15, 0.0, 0.05],
	["Banner", Color(0.5, 0.1, 0.1), 0, 0.2, 0.0, 0.08],
	["Old chest", Color(0.36, 0.22, 0.12), -1, 0.0, 0.0, 0.1],
	["Old chest", Color(0.4, 0.9, 0.4), -1, 0.0, 0.8, 0.04],
	["Old chest", Color(0.4, 0.65, 1.0), -1, 0.0, 0.8, 0.04],
	["Old chest", Color(0.75, 0.45, 1.0), -1, 0.0, 0.9, 0.04],
	["Old chest", Color(1.0, 0.62, 0.12), -1, 0.0, 1.0, 0.04],
	["Old chest", Color(1.0, 0.82, 0.35), -1, 0.0, 0.3, 0.04],
	["Old chest", Color(0.34, 0.32, 0.29), -1, 0.0, 0.0, 0.06],
	["Steel", Color(0.62, 0.65, 0.7), -1, 0.0, 0.0, 0.05],
	["Iron", Color(0.22, 0.22, 0.24), -1, 0.0, 0.0, 0.06],
	["Stump", Color(0.42, 0.29, 0.17), -1, 0.0, 0.0, 0.12],
	["Straw", Color(0.85, 0.72, 0.38), -1, 0.0, 0.0, 0.18],
	["Sacking", Color(0.66, 0.56, 0.4), -1, 0.0, 0.0, 0.1],
	["Map", Color(0.88, 0.8, 0.6), -1, 0.0, 0.0, 0.06],
	["Crate", Color(0.58, 0.4, 0.22), -1, 0.0, 0.0, 0.1],
	["Iron band", Color(0.3, 0.3, 0.32), -1, 0.0, 0.0, 0.05],
	["Urn", Color(0.55, 0.35, 0.22), 0, 0.2, 0.0, 0.12],
]

static var NAMES: Array = []
static var COLORS: Array = []
static var TIER := PackedInt32Array()
static var DIG_TIME := PackedFloat32Array()
static var GLOW := PackedFloat32Array()
static var JITTER := PackedFloat32Array()


static func _static_init() -> void:
	for row: Array in DEFS:
		NAMES.append(row[0])
		COLORS.append(row[1])
		TIER.append(row[2])
		DIG_TIME.append(row[3])
		GLOW.append(row[4])
		JITTER.append(row[5])


static func is_ground(b: int) -> bool:
	return b >= DIRT and b <= BEDROCK


static func is_treasure(b: int) -> bool:
	return b == RELIC or b == CHEST or b == CHEST_TRIM


static func is_natural(b: int) -> bool:
	return b >= DIRT and b <= DEEPROCK


# Hidden-room masonry: breaking any of it is how you get in.
static func is_vault(b: int) -> bool:
	return b >= VAULT_BRICK and b <= BANNER or b == URN


static func is_loot_chest(b: int) -> bool:
	return b >= LOOT_CHEST and b <= LOOT_EMPTY


# Whether a pick (or a blast) of this tier breaks the block. Treasure comes out whole instead.
static func diggable(b: int, tier: int) -> bool:
	var t := TIER[b]
	return t >= 0 and t <= tier and not is_treasure(b)
