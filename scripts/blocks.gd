extends RefCounted
# Block ids and their properties. Every per-block table is indexed by block id.

const AIR := 0
const GRASS := 1
const DIRT := 2
const SAND := 3
const CLAY := 4
const GRAVEL := 5
const STONE := 6
const SLATE := 7
const BEDROCK := 8
const LOG := 9
const LEAVES := 10
const RELIC := 11
const CHEST := 12

# Layers of the tile texture array (painted in textures.gd, in this order).
const TX_GRASS_TOP := 0
const TX_GRASS_SIDE := 1
const TX_DIRT := 2
const TX_SAND := 3
const TX_CLAY := 4
const TX_GRAVEL := 5
const TX_STONE := 6
const TX_SLATE := 7
const TX_BEDROCK := 8
const TX_LOG_SIDE := 9
const TX_LOG_TOP := 10
const TX_LEAVES := 11
const TX_RELIC := 12
const TX_CHEST_SIDE := 13
const TX_CHEST_TOP := 14

const NAMES := ["Air", "Grass", "Dirt", "Sand", "Clay", "Gravel", "Stone", "Slate", "Bedrock", "Log", "Leaves", "Glinting soil", "Buried chest"]
# Seconds of digging to break a block; negative means it can't be dug.
const HARDNESS := [0.0, 0.45, 0.4, 0.35, 0.6, 0.5, 1.1, 1.7, -1.0, 0.9, 0.15, 0.6, 1.0]
# What goes in your pack when the block breaks.
const DROPS := [AIR, DIRT, DIRT, SAND, CLAY, GRAVEL, STONE, SLATE, AIR, LOG, AIR, AIR, AIR]
const TILE_TOP := [0, TX_GRASS_TOP, TX_DIRT, TX_SAND, TX_CLAY, TX_GRAVEL, TX_STONE, TX_SLATE, TX_BEDROCK, TX_LOG_TOP, TX_LEAVES, TX_RELIC, TX_CHEST_TOP]
const TILE_BOTTOM := [0, TX_DIRT, TX_DIRT, TX_SAND, TX_CLAY, TX_GRAVEL, TX_STONE, TX_SLATE, TX_BEDROCK, TX_LOG_TOP, TX_LEAVES, TX_RELIC, TX_CHEST_TOP]
const TILE_SIDE := [0, TX_GRASS_SIDE, TX_DIRT, TX_SAND, TX_CLAY, TX_GRAVEL, TX_STONE, TX_SLATE, TX_BEDROCK, TX_LOG_SIDE, TX_LEAVES, TX_RELIC, TX_CHEST_SIDE]
# Treasure blocks shimmer so they stand out in the dark.
const GLOW := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1]
# Whether the block keeps sky light off whatever is below it (tree tops don't).
const BLOCKS_SKY := [false, true, true, true, true, true, true, true, true, false, false, true, true]
# Blocks you can place, in hotbar order.
const HOTBAR := [DIRT, SAND, CLAY, GRAVEL, STONE, SLATE, LOG]


static func is_treasure(b: int) -> bool:
	return b == RELIC or b == CHEST
