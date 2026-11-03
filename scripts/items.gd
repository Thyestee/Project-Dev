extends RefCounted
# Gear: pickaxes, swords, maces and shields. A piece of gear is a plain dictionary, so it goes
# straight into the save:
#   {"kind", "tier", "rarity", "affixes": [{"id", "value"}], "legend", "rerolls", "inscription"}
# The tier is the material, from wood to starmetal (see MATERIALS): every step digs harder rock,
# swings a little faster and hits harder. Gear you find in hidden rooms comes with random affixes,
# more the rarer it is; legendary gear also has one legendary affix that changes how it plays.
# Some affixes never turn up that way: you learn them from scrolls, and the forge inscribes them.

const Treasures := preload("res://scripts/treasures.gd")
const Blocks := preload("res://scripts/blocks.gd")

const KINDS := ["pickaxe", "sword", "mace", "shield"]
const KIND_NAMES := {"pickaxe": "Pickaxe", "sword": "Sword", "mace": "Mace", "shield": "Shield"}
const MATERIALS := ["Wooden", "Copper", "Iron", "Steel", "Gold", "Diamond", "Mithril", "Adamant", "Starmetal"]
const TOP_TIER := 8
const TIER_COLORS := [Color(0.66, 0.47, 0.28), Color(0.86, 0.5, 0.3), Color(0.64, 0.65, 0.68), Color(0.58, 0.72, 0.86), Color(1.0, 0.8, 0.3),
	Color(0.5, 0.96, 1.0), Color(0.62, 0.86, 1.0), Color(0.9, 0.25, 0.5), Color(1.0, 0.95, 0.72)]
# What each pickaxe digs, by tier.
const HARDNESS_TEXT := ["nothing", "dirt, sand, clay, gravel, coal, copper and iron ore", "stone, silver ore, amethyst and everything softer",
	"slate, gold ore, rubies and everything softer", "deeprock, diamonds and everything softer", "basalt, mithril ore, sapphires and everything softer",
	"obsidian, adamant ore, emeralds and everything softer", "magmarock, starmetal ore and everything softer", "every kind of rock, even voidstone"]
const RARITY_NAMES := Treasures.RARITY_NAMES
const RARITY_COLORS := Treasures.RARITY_COLORS
const RARITY_BUFF := [0.0, 0.1, 0.2, 0.3, 0.5]
const RARITY_AFFIXES := [0, 1, 2, 3, 3]

# By tier: how hard gear hits, and for a pickaxe the radius of its dent in cubes and how fast it
# swings. Each step is a little better than the last.
const POWER := [0.75, 1.0, 1.42, 2.0, 2.75, 3.75, 5.0, 6.6, 8.6]
const DIG_RADIUS := [3.0, 3.0, 3.3, 3.6, 3.9, 4.3, 4.7, 5.2, 5.7]
const DIG_SPEED := [1.0, 1.0, 1.1, 1.2, 1.31, 1.43, 1.56, 1.7, 1.85]
const SWING_SPEED := [0.95, 1.0, 1.04, 1.08, 1.12, 1.16, 1.2, 1.24, 1.28]
const REACH_GROWTH := [1.0, 1.0, 1.02, 1.04, 1.06, 1.08, 1.1, 1.12, 1.14]
const SHIELD_GUARD := [0.45, 0.5, 0.58, 0.64, 0.69, 0.74, 0.78, 0.81, 0.84]
const BASE_DAMAGE := {"pickaxe": 6.0, "sword": 10.0, "mace": 18.0}
const ATTACK_TIME := {"pickaxe": 0.6, "sword": 0.5, "mace": 0.95}
const STAMINA := {"pickaxe": 3.0, "sword": 9.0, "mace": 16.0, "shield": 0.6}
const REACH := {"pickaxe": 2.4, "sword": 2.7, "mace": 2.5}

# A roll gives a whole number from min to max; "scale" turns it into the number shown and used.
# Affixes with a "scroll" name only come from scrolls (see Goods), never at random.
const AFFIXES := {
	"damage": {"text": "+%s%% damage", "min": 8, "max": 20, "kinds": ["sword", "mace"]},
	"speed": {"text": "+%s%% attack speed", "min": 8, "max": 20, "kinds": ["sword", "mace"]},
	"crit": {"text": "+%s%% chance of a critical hit", "min": 5, "max": 12, "kinds": ["sword", "mace"]},
	"knockback": {"text": "+%s%% knockback", "min": 25, "max": 60, "kinds": ["sword", "mace"]},
	"stun": {"text": "+%s%% stun time", "min": 30, "max": 70, "kinds": ["mace"]},
	"reach": {"text": "+%s%% reach", "min": 10, "max": 20, "kinds": ["sword"]},
	"bounty": {"text": "+%s%% coins from enemies", "min": 15, "max": 40, "kinds": ["sword", "mace"]},
	"endurance": {"text": "-%s%% stamina cost", "min": 15, "max": 35, "kinds": ["pickaxe", "sword", "mace", "shield"]},
	"vitality": {"text": "+%s max health", "min": 10, "max": 25, "kinds": ["pickaxe", "sword", "mace", "shield"]},
	"swift": {"text": "+%s%% move speed", "min": 5, "max": 12, "kinds": ["pickaxe", "shield"]},
	"dig_speed": {"text": "+%s%% dig speed", "min": 8, "max": 20, "kinds": ["pickaxe"]},
	"dig_size": {"text": "+%s%% dig size", "min": 8, "max": 20, "kinds": ["pickaxe"]},
	"guard": {"text": "+%s%% block", "min": 4, "max": 10, "kinds": ["shield"]},
	"leech": {"text": "Heals you for %s%% of the damage dealt", "min": 2, "max": 8, "kinds": ["sword", "mace"], "scroll": "Leeching"},
	"burn": {"text": "%s%% chance to set enemies on fire", "min": 10, "max": 30, "kinds": ["sword", "mace"], "scroll": "Embers"},
	"regen": {"text": "+%s health per second", "min": 5, "max": 20, "scale": 0.1, "kinds": ["pickaxe", "sword", "mace", "shield"], "scroll": "Mending"},
	"thorns": {"text": "Blocked blows deal %s%% back to the attacker", "min": 20, "max": 60, "kinds": ["shield"], "scroll": "Thorns"},
	"lucky": {"text": "+%s%% ore from every blow", "min": 10, "max": 35, "kinds": ["pickaxe"], "scroll": "Fortune"},
	"prospector": {"text": "+%s%% coins from treasure", "min": 10, "max": 40, "kinds": ["pickaxe"], "scroll": "Appraisal"},
	"double": {"text": "%s%% chance of a double-strength blow", "min": 10, "max": 35, "kinds": ["pickaxe"], "scroll": "Might"},
}
# These work from any equipped piece of gear; every other affix only works on its own item.
const GLOBAL_AFFIXES := ["vitality", "regen", "swift"]

const LEGENDS := {
	"tunneler": {"kind": "pickaxe", "name": "Tunneler", "text": "Every swing also bores a tunnel 3 m straight ahead."},
	"harmonic": {"kind": "pickaxe", "name": "Harmonic", "text": "Digs through any rock, however hard."},
	"tempest": {"kind": "sword", "name": "Tempest", "text": "Every third swing unleashes a whirlwind that hits everything around you."},
	"phantom": {"kind": "sword", "name": "Phantom Edge", "text": "Every swing also sends a ghostly blade flying through your enemies."},
	"earthshaker": {"kind": "mace", "name": "Earthshaker", "text": "Every hit sends out a shockwave that hurts and stuns everything nearby and blasts the ground loose."},
	"thunder": {"kind": "mace", "name": "Thunderstrike", "text": "Every hit calls down lightning: double damage to the target and a jolt for everything near it."},
	"mirror": {"kind": "shield", "name": "Mirror Ward", "text": "Blocked arrows and darts fly back at whoever shot them, and blocked blows stun the attacker."},
	"aegis": {"kind": "shield", "name": "Aegis", "text": "A blow that would knock you out leaves you on 1 health and untouchable for 3 seconds instead. Recharges in 90 s."},
}

static var SCROLL_AFFIXES: Array[String] = []


static func _static_init() -> void:
	for id: String in AFFIXES:
		if AFFIXES[id].has("scroll"):
			SCROLL_AFFIXES.append(id)


# --- Making gear -------------------------------------------------------------------------------

static func make(kind: String, tier: int, rarity: int, rng: RandomNumberGenerator) -> Dictionary:
	var lowest := 1 if kind == "pickaxe" or kind == "mace" else 0
	var item := {"kind": kind, "tier": clampi(tier, lowest, TOP_TIER), "rarity": clampi(rarity, 0, 4), "affixes": [], "legend": "", "rerolls": 0, "inscription": {}}
	for n in RARITY_AFFIXES[item["rarity"]]:
		var affix := roll_affix(item, rng)
		if not affix.is_empty():
			item["affixes"].append(affix)
	if item["rarity"] == 4:
		var options: Array = []
		for id: String in LEGENDS:
			if LEGENDS[id]["kind"] == kind:
				options.append(id)
		item["legend"] = options[rng.randi_range(0, options.size() - 1)]
	return item


# A random affix the item doesn't have yet (so a reforge always changes something). Scroll
# affixes never come up.
static func roll_affix(item: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var taken: Array = []
	for a: Dictionary in item["affixes"]:
		taken.append(a["id"])
	var pool: Array = []
	for id: String in AFFIXES:
		if (AFFIXES[id]["kinds"] as Array).has(item["kind"]) and not taken.has(id) and not AFFIXES[id].has("scroll"):
			pool.append(id)
	if pool.is_empty():
		return {}
	var id: String = pool[rng.randi_range(0, pool.size() - 1)]
	var def: Dictionary = AFFIXES[id]
	# Rarer gear rolls towards the top of the range.
	var roll := 1.0 - pow(1.0 - rng.randf(), 1.0 + 0.35 * maxi(0, int(item["rarity"]) - 1))
	return {"id": id, "value": roundi(lerpf(float(def["min"]), float(def["max"]), roll))}


# The anvil: swaps one affix for a different random one.
static func reforge(item: Dictionary, index: int, rng: RandomNumberGenerator) -> void:
	var affix := roll_affix(item, rng)
	if affix.is_empty():
		return
	item["affixes"][index] = affix
	item["rerolls"] = int(item["rerolls"]) + 1


# Wooden gear can't be improved; the rest goes up a step at a time, up to starmetal.
static func can_upgrade(item: Dictionary) -> bool:
	return not item.is_empty() and int(item["tier"]) >= 1 and int(item["tier"]) < TOP_TIER


static func fits_affix(item: Dictionary, id: String) -> bool:
	return AFFIXES.has(id) and (AFFIXES[id]["kinds"] as Array).has(item["kind"])


# The material of gear found at a depth: about the one that digs the rock there, now and then a
# step better or worse.
static func tier_for_depth(depth: float, rng: RandomNumberGenerator) -> int:
	var t := 1.0 + Blocks.level(depth) + rng.randf_range(-0.9, 0.5)
	return clampi(floori(t), 1, TOP_TIER)


static func random_kind(rng: RandomNumberGenerator) -> String:
	var weights := {"pickaxe": 25.0, "sword": 28.0, "mace": 22.0, "shield": 25.0}
	var roll := rng.randf() * 100.0
	for kind: String in weights:
		roll -= weights[kind]
		if roll < 0.0:
			return kind
	return "sword"


static func loot(depth: float, rarity: int, rng: RandomNumberGenerator) -> Dictionary:
	return make(random_kind(rng), tier_for_depth(depth, rng), rarity, rng)


# A scroll's affix and how strong it is: deeper scrolls teach stronger versions.
static func scroll_value(id: String, depth: float, rng: RandomNumberGenerator) -> int:
	var def: Dictionary = AFFIXES[id]
	var k := clampf(Blocks.level(depth) / 7.0 + rng.randf_range(-0.12, 0.12), 0.0, 1.0)
	return roundi(lerpf(float(def["min"]), float(def["max"]), k))


# Turns gear read back from a save (where every number is a float) into proper gear, or {}.
static func sanitize(d) -> Dictionary:
	if not d is Dictionary or not KINDS.has(str(d.get("kind", ""))):
		return {}
	var kind := str(d["kind"])
	var lowest := 1 if kind == "pickaxe" or kind == "mace" else 0
	var item := {"kind": kind, "tier": clampi(int(d.get("tier", 1)), lowest, TOP_TIER), "rarity": clampi(int(d.get("rarity", 0)), 0, 4),
		"affixes": [], "legend": str(d.get("legend", "")), "rerolls": maxi(0, int(d.get("rerolls", 0))), "inscription": {}}
	for a in d.get("affixes", []):
		if a is Dictionary and AFFIXES.has(str(a.get("id", ""))):
			item["affixes"].append({"id": str(a["id"]), "value": int(a.get("value", 0))})
	var ins = d.get("inscription", {})
	if ins is Dictionary and fits_affix(item, str(ins.get("id", ""))):
		item["inscription"] = {"id": str(ins["id"]), "value": int(ins.get("value", 0))}
	if not LEGENDS.has(item["legend"]) or LEGENDS[item["legend"]]["kind"] != item["kind"]:
		item["legend"] = ""
	return item


# Gear saved by 0.5 or earlier: tiers went copper, iron, steel, diamond (shields wooden, iron,
# steel, diamond), and the metal detector's affix became ore luck. Bows are gone: {}.
static func from_old(d) -> Dictionary:
	if not d is Dictionary or str(d.get("kind", "")) == "bow":
		return {}
	var out: Dictionary = d.duplicate(true)
	var old := clampi(int(d.get("tier", 0)), 0, 3)
	if str(d.get("kind", "")) == "shield":
		out["tier"] = [0, 2, 3, 5][old]
	else:
		out["tier"] = [1, 2, 3, 5][old]
	var affixes: Array = []
	for a in d.get("affixes", []):
		if not a is Dictionary:
			continue
		var id := str(a.get("id", ""))
		var value := int(a.get("value", 0))
		if id == "sense":
			id = "lucky"
			value = 10 + (clampi(value, 2, 6) - 2) * 5
		affixes.append({"id": id, "value": value})
	out["affixes"] = affixes
	return sanitize(out)


# --- Numbers -----------------------------------------------------------------------------------

static func affix(item: Dictionary, id: String) -> float:
	if item.is_empty():
		return 0.0
	var total := 0.0
	for a: Dictionary in item["affixes"]:
		if a["id"] == id:
			total += float(a["value"])
	var ins: Dictionary = item.get("inscription", {})
	if not ins.is_empty() and ins["id"] == id:
		total += float(ins["value"])
	return total * float(AFFIXES[id].get("scale", 1.0))


static func buff(item: Dictionary) -> float:
	return RARITY_BUFF[item["rarity"]]


static func legend(item: Dictionary) -> String:
	return "" if item.is_empty() else str(item.get("legend", ""))


static func damage(item: Dictionary) -> float:
	var base: float = BASE_DAMAGE.get(item["kind"], 0.0)
	return base * POWER[item["tier"]] * (1.0 + buff(item)) * (1.0 + affix(item, "damage") / 100.0)


static func attack_time(item: Dictionary) -> float:
	var t: float = ATTACK_TIME.get(item["kind"], 0.6)
	return t / (SWING_SPEED[item["tier"]] * (1.0 + affix(item, "speed") / 100.0))


static func reach(item: Dictionary) -> float:
	return float(REACH.get(item["kind"], 2.4)) * REACH_GROWTH[item["tier"]] * (1.0 + affix(item, "reach") / 100.0)


static func stamina_cost(item: Dictionary) -> float:
	return float(STAMINA.get(item["kind"], 5.0)) * (1.0 - affix(item, "endurance") / 100.0)


# Share of the damage from in front that the shield stops.
static func guard(item: Dictionary) -> float:
	return minf(0.92, SHIELD_GUARD[item["tier"]] * (1.0 + buff(item)) + affix(item, "guard") / 100.0)


# How fast a pickaxe swings and how big a dent it leaves, from its material, rarity and affixes.
static func dig_speed(item: Dictionary) -> float:
	return DIG_SPEED[item["tier"]] * (1.0 + buff(item)) * (1.0 + affix(item, "dig_speed") / 100.0)


static func dig_radius(item: Dictionary) -> float:
	return DIG_RADIUS[item["tier"]] * (1.0 + buff(item) * 0.5) * (1.0 + affix(item, "dig_size") / 100.0)


# The hardest rock the pickaxe digs (see Blocks.TIER).
static func hardness(item: Dictionary) -> int:
	return TOP_TIER if legend(item) == "harmonic" else int(item["tier"])


static func salvage_value(item: Dictionary) -> int:
	return roundi([8, 35, 100, 260, 700][item["rarity"]] * POWER[item["tier"]])


static func reforge_cost(item: Dictionary) -> int:
	return roundi([0, 50, 120, 300, 700][item["rarity"]] * POWER[item["tier"]] * (1.0 + 0.5 * float(item["rerolls"])))


static func inscribe_cost(item: Dictionary) -> int:
	return roundi(150.0 * POWER[item["tier"]])


# --- Words -------------------------------------------------------------------------------------

static func base_name(item: Dictionary) -> String:
	return "%s %s" % [MATERIALS[item["tier"]], KIND_NAMES[item["kind"]]]


# The big name: legendary gear has its own.
static func title(item: Dictionary) -> String:
	var l := legend(item)
	return LEGENDS[l]["name"] if l != "" else base_name(item)


static func subtitle(item: Dictionary) -> String:
	return "%s %s" % [RARITY_NAMES[item["rarity"]], base_name(item)]


static func color(item: Dictionary) -> Color:
	return RARITY_COLORS[item["rarity"]]


static func affix_text(a: Dictionary) -> String:
	var def: Dictionary = AFFIXES[a["id"]]
	var value := float(a["value"]) * float(def.get("scale", 1.0))
	var shown := ("%.1f" % value) if def.has("scale") else str(int(value))
	return String(def["text"]) % shown


static func stat_lines(item: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	match item["kind"]:
		"pickaxe":
			lines.append("Digs %s" % HARDNESS_TEXT[hardness(item)])
			lines.append("Dents %.2f m across  ·  digs ×%.2f as fast" % [dig_radius(item) * 0.25, dig_speed(item)])
		"sword", "mace":
			lines.append("%d damage  ·  %.2f s per swing  ·  %.1f m reach" % [roundi(damage(item)), attack_time(item), reach(item)])
		"shield":
			lines.append("Blocks %d%% of the damage from in front" % roundi(guard(item) * 100.0))
	if buff(item) > 0.0:
		lines.append("%s bonus: +%d%%" % [RARITY_NAMES[item["rarity"]], roundi(buff(item) * 100.0)])
	if int(item["tier"]) == 0:
		lines.append("Wood can't be improved at the forge.")
	return lines
