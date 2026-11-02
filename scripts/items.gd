extends RefCounted
# Gear: pickaxes, swords, maces, bows and shields. A piece of gear is a plain dictionary, so it
# goes straight into the save:
#   {"kind", "tier", "rarity", "affixes": [{"id", "value"}], "legend", "rerolls"}
# The tier is the material (copper to diamond). Rarer gear is stronger and carries more affixes;
# legendary gear also has one legendary affix that changes how it plays.

const Treasures := preload("res://scripts/treasures.gd")

const KINDS := ["pickaxe", "sword", "mace", "bow", "shield"]
const KIND_NAMES := {"pickaxe": "Pickaxe", "sword": "Sword", "mace": "Mace", "bow": "Bow", "shield": "Shield"}
const TIER_NAMES := {
	"pickaxe": ["Copper", "Iron", "Steel", "Diamond"],
	"sword": ["Copper", "Iron", "Steel", "Diamond"],
	"mace": ["Copper", "Iron", "Steel", "Diamond"],
	"bow": ["Ash", "Yew", "Ironwood", "Crystal"],
	"shield": ["Wooden", "Iron", "Steel", "Diamond"],
}
const TIER_COLORS := [Color(0.86, 0.5, 0.3), Color(0.64, 0.65, 0.68), Color(0.58, 0.72, 0.86), Color(0.5, 0.96, 1.0)]
const WOOD_COLORS := [Color(0.66, 0.47, 0.28), Color(0.5, 0.3, 0.17), Color(0.34, 0.3, 0.3), Color(0.55, 0.88, 0.97)]
const HARDNESS_TEXT := ["dirt, sand, clay and gravel", "stone and everything softer", "slate and everything softer", "every kind of rock"]
const RARITY_NAMES := Treasures.RARITY_NAMES
const RARITY_COLORS := Treasures.RARITY_COLORS
const RARITY_BUFF := [0.0, 0.1, 0.2, 0.3, 0.5]
const RARITY_AFFIXES := [0, 1, 2, 3, 3]

const PICK_DAMAGE := [6.0, 9.0, 13.0, 18.0]
const SWORD_DAMAGE := [10.0, 16.0, 25.0, 38.0]
const MACE_DAMAGE := [18.0, 28.0, 44.0, 66.0]
const BOW_DAMAGE := [12.0, 19.0, 30.0, 45.0]
const SHIELD_GUARD := [0.5, 0.62, 0.72, 0.8]
const ATTACK_TIME := {"pickaxe": 0.6, "sword": 0.5, "mace": 0.95, "bow": 0.75}
const STAMINA := {"pickaxe": 3.0, "sword": 9.0, "mace": 16.0, "bow": 7.0, "shield": 0.6}
const REACH := {"pickaxe": 2.4, "sword": 2.7, "mace": 2.5}

# A roll gives a whole number from min to max; "scale" turns it into the number shown and used.
const AFFIXES := {
	"damage": {"text": "+%s%% damage", "min": 8, "max": 20, "kinds": ["sword", "mace", "bow"]},
	"speed": {"text": "+%s%% attack speed", "min": 8, "max": 20, "kinds": ["sword", "mace"]},
	"draw": {"text": "+%s%% draw speed", "min": 10, "max": 25, "kinds": ["bow"]},
	"crit": {"text": "+%s%% chance of a critical hit", "min": 5, "max": 12, "kinds": ["sword", "mace", "bow"]},
	"leech": {"text": "Heals you for %s%% of the damage dealt", "min": 2, "max": 6, "kinds": ["sword", "mace", "bow"]},
	"burn": {"text": "%s%% chance to set enemies on fire", "min": 10, "max": 25, "kinds": ["sword", "mace", "bow"]},
	"knockback": {"text": "+%s%% knockback", "min": 25, "max": 60, "kinds": ["sword", "mace"]},
	"stun": {"text": "+%s%% stun time", "min": 30, "max": 70, "kinds": ["mace"]},
	"reach": {"text": "+%s%% reach", "min": 10, "max": 20, "kinds": ["sword"]},
	"thrifty": {"text": "%s%% chance not to use up an arrow", "min": 20, "max": 45, "kinds": ["bow"]},
	"pierce": {"text": "Arrows go through %s enemy", "min": 1, "max": 1, "kinds": ["bow"]},
	"bounty": {"text": "+%s%% coins from enemies", "min": 15, "max": 40, "kinds": ["sword", "mace", "bow"]},
	"endurance": {"text": "-%s%% stamina cost", "min": 15, "max": 35, "kinds": ["pickaxe", "sword", "mace", "bow", "shield"]},
	"vitality": {"text": "+%s max health", "min": 10, "max": 25, "kinds": ["pickaxe", "sword", "mace", "bow", "shield"]},
	"regen": {"text": "+%s health per second", "min": 5, "max": 15, "scale": 0.1, "kinds": ["pickaxe", "shield"]},
	"swift": {"text": "+%s%% move speed", "min": 5, "max": 12, "kinds": ["pickaxe", "shield"]},
	"dig_speed": {"text": "+%s%% dig speed", "min": 8, "max": 20, "kinds": ["pickaxe"]},
	"dig_size": {"text": "+%s%% dig size", "min": 8, "max": 20, "kinds": ["pickaxe"]},
	"prospector": {"text": "+%s%% coins from treasure", "min": 10, "max": 30, "kinds": ["pickaxe"]},
	"double": {"text": "%s%% chance of a double-strength blow", "min": 10, "max": 30, "kinds": ["pickaxe"]},
	"sense": {"text": "+%s m metal detector range", "min": 2, "max": 6, "kinds": ["pickaxe"]},
	"guard": {"text": "+%s%% block", "min": 4, "max": 10, "kinds": ["shield"]},
	"thorns": {"text": "Blocked blows deal %s%% back to the attacker", "min": 20, "max": 50, "kinds": ["shield"]},
}
# These work from any equipped piece of gear; every other affix only works on its own item.
const GLOBAL_AFFIXES := ["vitality", "regen", "swift", "sense"]

const LEGENDS := {
	"tunneler": {"kind": "pickaxe", "name": "Tunneler", "text": "Every swing also bores a tunnel 3 m straight ahead."},
	"harmonic": {"kind": "pickaxe", "name": "Harmonic", "text": "Digs through any rock, however hard."},
	"tempest": {"kind": "sword", "name": "Tempest", "text": "Every third swing unleashes a whirlwind that hits everything around you."},
	"phantom": {"kind": "sword", "name": "Phantom Edge", "text": "Every swing also sends a ghostly blade flying through your enemies."},
	"earthshaker": {"kind": "mace", "name": "Earthshaker", "text": "Every hit sends out a shockwave that hurts and stuns everything nearby and blasts the ground loose."},
	"thunder": {"kind": "mace", "name": "Thunderstrike", "text": "Every hit calls down lightning: double damage to the target and a jolt for everything near it."},
	"volley": {"kind": "bow", "name": "Volley", "text": "Fires five arrows in a fan for the price of one."},
	"blast": {"kind": "bow", "name": "Blastfletch", "text": "Arrows explode where they land."},
	"mirror": {"kind": "shield", "name": "Mirror Ward", "text": "Blocked arrows fly back at whoever shot them, and blocked blows stun the attacker."},
	"aegis": {"kind": "shield", "name": "Aegis", "text": "A blow that would knock you out leaves you on 1 health and untouchable for 3 seconds instead. Recharges in 90 s."},
}


# --- Making gear -------------------------------------------------------------------------------

static func make(kind: String, tier: int, rarity: int, rng: RandomNumberGenerator) -> Dictionary:
	var item := {"kind": kind, "tier": clampi(tier, 0, 3), "rarity": clampi(rarity, 0, 4), "affixes": [], "legend": "", "rerolls": 0}
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


# A random affix the item doesn't have yet (so a reforge always changes something).
static func roll_affix(item: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var taken: Array = []
	for a: Dictionary in item["affixes"]:
		taken.append(a["id"])
	var pool: Array = []
	for id: String in AFFIXES:
		if (AFFIXES[id]["kinds"] as Array).has(item["kind"]) and not taken.has(id):
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


# The material goes up about one step every 11 m down.
static func tier_for_depth(depth: float, rng: RandomNumberGenerator) -> int:
	var t := clampf(depth / 11.0, 0.0, 3.0)
	var tier := floori(t)
	if rng.randf() < t - tier:
		tier += 1
	return clampi(tier, 0, 3)


static func random_kind(rng: RandomNumberGenerator) -> String:
	var weights := {"pickaxe": 22.0, "sword": 22.0, "mace": 18.0, "bow": 20.0, "shield": 18.0}
	var roll := rng.randf() * 100.0
	for kind: String in weights:
		roll -= weights[kind]
		if roll < 0.0:
			return kind
	return "sword"


static func loot(depth: float, rarity: int, rng: RandomNumberGenerator) -> Dictionary:
	return make(random_kind(rng), tier_for_depth(depth, rng), rarity, rng)


# Turns gear read back from a save (where every number is a float) into proper gear, or {}.
static func sanitize(d) -> Dictionary:
	if not d is Dictionary or not KINDS.has(str(d.get("kind", ""))):
		return {}
	var item := {"kind": str(d["kind"]), "tier": clampi(int(d.get("tier", 0)), 0, 3), "rarity": clampi(int(d.get("rarity", 0)), 0, 4),
		"affixes": [], "legend": str(d.get("legend", "")), "rerolls": maxi(0, int(d.get("rerolls", 0)))}
	for a in d.get("affixes", []):
		if a is Dictionary and AFFIXES.has(str(a.get("id", ""))):
			item["affixes"].append({"id": str(a["id"]), "value": int(a.get("value", 0))})
	if not LEGENDS.has(item["legend"]) or LEGENDS[item["legend"]]["kind"] != item["kind"]:
		item["legend"] = ""
	return item


# --- Numbers -----------------------------------------------------------------------------------

static func affix(item: Dictionary, id: String) -> float:
	if item.is_empty():
		return 0.0
	var total := 0.0
	for a: Dictionary in item["affixes"]:
		if a["id"] == id:
			total += float(a["value"]) * float(AFFIXES[id].get("scale", 1.0))
	return total


static func buff(item: Dictionary) -> float:
	return RARITY_BUFF[item["rarity"]]


static func legend(item: Dictionary) -> String:
	return "" if item.is_empty() else str(item.get("legend", ""))


static func damage(item: Dictionary) -> float:
	var base := 0.0
	match item["kind"]:
		"pickaxe":
			base = PICK_DAMAGE[item["tier"]]
		"sword":
			base = SWORD_DAMAGE[item["tier"]]
		"mace":
			base = MACE_DAMAGE[item["tier"]]
		"bow":
			base = BOW_DAMAGE[item["tier"]]
	return base * (1.0 + buff(item)) * (1.0 + affix(item, "damage") / 100.0)


static func attack_time(item: Dictionary) -> float:
	var t: float = ATTACK_TIME.get(item["kind"], 0.6)
	var bonus := affix(item, "draw") if item["kind"] == "bow" else affix(item, "speed")
	return t / (1.0 + bonus / 100.0)


static func reach(item: Dictionary) -> float:
	return float(REACH.get(item["kind"], 2.4)) * (1.0 + affix(item, "reach") / 100.0)


static func stamina_cost(item: Dictionary) -> float:
	return float(STAMINA.get(item["kind"], 5.0)) * (1.0 - affix(item, "endurance") / 100.0)


# Share of the damage from in front that the shield stops.
static func guard(item: Dictionary) -> float:
	return minf(0.92, SHIELD_GUARD[item["tier"]] * (1.0 + buff(item)) + affix(item, "guard") / 100.0)


static func dig_speed(item: Dictionary) -> float:
	return (1.0 + buff(item)) * (1.0 + affix(item, "dig_speed") / 100.0)


static func dig_size(item: Dictionary) -> float:
	return (1.0 + buff(item)) * (1.0 + affix(item, "dig_size") / 100.0)


# The hardest rock the pickaxe digs (see Blocks.TIER).
static func hardness(item: Dictionary) -> int:
	return 3 if legend(item) == "harmonic" else int(item["tier"])


static func salvage_value(item: Dictionary) -> int:
	return roundi([8, 35, 100, 260, 700][item["rarity"]] * (1.0 + 0.6 * float(item["tier"])))


static func reforge_cost(item: Dictionary) -> int:
	return roundi([0, 50, 120, 300, 700][item["rarity"]] * (1.0 + 0.6 * float(item["tier"])) * (1.0 + 0.5 * float(item["rerolls"])))


# --- Words -------------------------------------------------------------------------------------

static func base_name(item: Dictionary) -> String:
	return "%s %s" % [TIER_NAMES[item["kind"]][item["tier"]], KIND_NAMES[item["kind"]]]


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
			lines.append("Dig speed ×%.2f  ·  dig size ×%.2f" % [dig_speed(item), dig_size(item)])
		"sword", "mace":
			lines.append("%d damage  ·  %.2f s per swing" % [roundi(damage(item)), attack_time(item)])
		"bow":
			lines.append("%d damage at full draw  ·  %.2f s to draw" % [roundi(damage(item)), attack_time(item)])
		"shield":
			lines.append("Blocks %d%% of the damage from in front" % roundi(guard(item) * 100.0))
	if buff(item) > 0.0:
		lines.append("%s bonus: +%d%%" % [RARITY_NAMES[item["rarity"]], roundi(buff(item) * 100.0)])
	return lines
