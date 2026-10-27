class_name Weapons
## Original weapon roster (same stats as the libGDX game) plus wall-buy prices.

static func make(id: String) -> WeaponDef:
	match id:
		"sidearm": return WeaponDef.new("sidearm", "Volt Sidearm", 30, 0.35).setup({mag_size = 12, reload_time = 1.2, spread_deg = 0.5, recoil = 1.6, color = Color(0.45, 0.5, 0.55)})
		"scatter": return WeaponDef.new("scatter", "Scatterbolt", 25, 0.8).setup({pellets = 5, mag_size = 6, reload_time = 2.0, spread_deg = 5.0, recoil = 4.0, color = Color(0.55, 0.38, 0.22)})
		"rifle": return WeaponDef.new("rifle", "Pulse Rifle", 40, 0.12).setup({mag_size = 30, reload_time = 1.8, automatic = true, spread_deg = 1.0, recoil = 1.1, color = Color(0.25, 0.32, 0.25)})
		"cannon": return WeaponDef.new("cannon", "Rail Lancer", 200, 0.9).setup({pierce = 2, mag_size = 5, reload_time = 2.2, spread_deg = 0.1, recoil = 5.0, color = Color(0.2, 0.45, 0.65)})
		"smg": return WeaponDef.new("smg", "Buzzsaw SMG", 22, 0.07).setup({mag_size = 40, reload_time = 1.9, automatic = true, spread_deg = 2.2, recoil = 0.8, color = Color(0.3, 0.3, 0.32)})
		"nova": return WeaponDef.new("nova", "Nova Disruptor", 400, 0.6).setup({splash = 60.0, mag_size = 4, reload_time = 2.5, spread_deg = 0.3, recoil = 3.5, color = Color(0.2, 0.85, 0.7)})
	return null

const ALL_IDS := ["sidearm", "scatter", "rifle", "cannon", "smg", "nova"]
const STARTER := "sidearm"

## Wall-buy chalk outlines: weapon id -> price. Owned weapons cannot be re-bought (ammo is unlimited reserve; reload refills).
const WALL_PRICES := {"smg": 1000, "scatter": 1200, "rifle": 1400}

static func by_id(id: String) -> WeaponDef:
	return make(id)

## Rebuilds a weapon from id + Forge tier (used for network state and tests).
static func at(id: String, tier: int) -> WeaponDef:
	var w := make(id)
	if w == null:
		w = make(STARTER)
	for i in range(clampi(tier, 0, WeaponDef.MAX_TIER)):
		w = w.upgraded_version()
	return w
