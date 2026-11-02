extends RefCounted
# Block ids and their properties. Every per-block table is indexed by block id.
# Blocks are small cubes, World.VOXEL metres on a side.

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
const TROPHY := 34   # 34 to 38: one colour per treasure rarity

const NAMES := ["Air", "Dirt", "Sand", "Clay", "Gravel", "Stone", "Slate", "Deeprock", "Bedrock",
	"Glinting soil", "Buried chest", "Buried chest", "Floorboards", "Wooden wall", "Beam", "Brick",
	"Window", "Lantern", "Workbench", "Vise", "Rug", "Rug", "Bed", "Pillow", "Book", "Book", "Book",
	"Fire", "Fireplace", "Panelling", "Wallpaper", "Gold", "Plant", "Pot",
	"Trophy", "Trophy", "Trophy", "Trophy", "Trophy"]
const COLORS := [Color(0, 0, 0), Color(0.45, 0.31, 0.2), Color(0.8, 0.7, 0.47), Color(0.62, 0.45, 0.36),
	Color(0.5, 0.48, 0.45), Color(0.5, 0.5, 0.52), Color(0.3, 0.33, 0.4), Color(0.24, 0.18, 0.28),
	Color(0.13, 0.12, 0.12), Color(1.0, 0.78, 0.25), Color(0.45, 0.28, 0.14), Color(1.0, 0.8, 0.3),
	Color(0.64, 0.46, 0.29), Color(0.52, 0.38, 0.25), Color(0.33, 0.22, 0.14), Color(0.56, 0.36, 0.3),
	Color(0.72, 0.86, 1.0), Color(1.0, 0.82, 0.45), Color(0.72, 0.56, 0.36), Color(0.3, 0.31, 0.33),
	Color(0.62, 0.16, 0.14), Color(0.9, 0.7, 0.3), Color(0.22, 0.36, 0.62), Color(0.92, 0.9, 0.85),
	Color(0.6, 0.15, 0.12), Color(0.18, 0.42, 0.22), Color(0.18, 0.25, 0.55), Color(1.0, 0.55, 0.15),
	Color(0.46, 0.45, 0.43), Color(0.48, 0.3, 0.18), Color(0.4, 0.5, 0.38), Color(1.0, 0.8, 0.3),
	Color(0.3, 0.58, 0.25), Color(0.72, 0.38, 0.22),
	Color(0.85, 0.85, 0.85), Color(0.5, 0.9, 0.45), Color(0.45, 0.7, 1.0), Color(0.8, 0.55, 1.0), Color(1.0, 0.8, 0.25)]
# Which pick head can dig the block (see Upgrades.HEADS); -1 means nothing can.
const TIER := [-1, 0, 0, 0, 0, 1, 2, 3, -1, 0, 0, 0,
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]
# Seconds per pickaxe swing, before grip and head bonuses.
const DIG_TIME := [0.0, 0.32, 0.28, 0.42, 0.38, 0.5, 0.6, 0.75, 0.0, 0.4, 0.4, 0.4,
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
# How brightly the block glows on its own (treasure, lights, windows).
const GLOW := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.12, 0.6,
	0.0, 0.0, 0.0, 0.0, 0.85, 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.5, 0.0, 0.0, 0.0, 0.3, 0.0, 0.0,
	0.45, 0.45, 0.45, 0.45, 0.45]
# How much the shade varies from cube to cube: lots for soil and rock, a little for furniture.
const JITTER := [0.0, 0.22, 0.16, 0.2, 0.3, 0.22, 0.2, 0.22, 0.15, 0.12, 0.12, 0.08,
	0.1, 0.12, 0.08, 0.16, 0.04, 0.04, 0.08, 0.06, 0.08, 0.06, 0.06, 0.04, 0.12, 0.12, 0.12, 0.2, 0.2, 0.06, 0.05, 0.08, 0.2, 0.1,
	0.05, 0.05, 0.05, 0.05, 0.05]
# Blocks you can place, in hotbar order. Digging puts every natural block in your pack.
const HOTBAR := [DIRT, SAND, CLAY, GRAVEL, STONE, SLATE, DEEPROCK]


static func is_treasure(b: int) -> bool:
	return b == RELIC or b == CHEST or b == CHEST_TRIM


static func is_natural(b: int) -> bool:
	return b >= DIRT and b <= DEEPROCK
