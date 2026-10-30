class_name Weapons
## Original weapon roster (same stats as the libGDX game) plus wall-buy prices.

## Damage is tuned so round 1 (150 HP) falls to two sidearm body shots or one knife.
## recoil_pattern: repeating (up, right) kick multipliers; ads_time: seconds to aim down sights.
static func make(id: String) -> WeaponDef:
	match id:
		"sidearm": return WeaponDef.new("sidearm", "Volt Sidearm", 80, 0.28).setup({weight = 0.6, mag_size = 8, reserve_mags = 10, reload_time = 1.3, spread_deg = 0.5, recoil = 1.8, ads_time = 0.15,
			recoil_pattern = [Vector2(1, 0.1), Vector2(1, -0.2)], upgrade_name = "Volt Tempest", color = Color(0.45, 0.5, 0.55)})
		"scatter": return WeaponDef.new("scatter", "Scatterbolt", 60, 0.75).setup({weight = 1.25, pellets = 6, mag_size = 6, reserve_mags = 9, reload_time = 2.4, spread_deg = 5.0, recoil = 4.5, ads_time = 0.25,
			recoil_pattern = [Vector2(1, 0.3)], upgrade_name = "Thunderclap", color = Color(0.55, 0.38, 0.22)})
		"rifle": return WeaponDef.new("rifle", "Pulse Rifle", 110, 0.11).setup({weight = 1.0, mag_size = 30, reserve_mags = 6, reload_time = 2.0, automatic = true, spread_deg = 1.0, recoil = 1.1, ads_time = 0.25,
			recoil_pattern = [Vector2(1, 0.1), Vector2(1, 0.3), Vector2(0.9, -0.1), Vector2(1.1, 0.4), Vector2(0.8, -0.3)], upgrade_name = "Storm Pulse", color = Color(0.25, 0.32, 0.25)})
		"cannon": return WeaponDef.new("cannon", "Rail Lancer", 500, 0.9).setup({weight = 1.5, pierce = 2, mag_size = 5, reserve_mags = 6, reload_time = 2.6, spread_deg = 0.1, recoil = 5.0, ads_time = 0.35,
			recoil_pattern = [Vector2(1, 0)], upgrade_name = "Lance of Dusk", color = Color(0.2, 0.45, 0.65)})
		"smg": return WeaponDef.new("smg", "Buzzsaw SMG", 70, 0.07).setup({weight = 0.7, mag_size = 32, reserve_mags = 7, reload_time = 1.8, automatic = true, spread_deg = 2.2, recoil = 0.8, ads_time = 0.18,
			recoil_pattern = [Vector2(1, -0.4), Vector2(0.8, 0.5), Vector2(1, 0.2), Vector2(0.7, -0.6)], upgrade_name = "Hornet Swarm", color = Color(0.3, 0.3, 0.32)})
		"lmg": return WeaponDef.new("lmg", "Grinder LMG", 120, 0.09).setup({weight = 1.6, mag_size = 75, reserve_mags = 5, reload_time = 3.6, automatic = true, spread_deg = 1.8, recoil = 1.0, ads_time = 0.4,
			recoil_pattern = [Vector2(1, 0.5), Vector2(1.1, 0.2), Vector2(0.9, 0.6)], upgrade_name = "Meatgrinder 9000", color = Color(0.28, 0.27, 0.22)})
		"nova": return WeaponDef.new("nova", "Nova Disruptor", 1000, 0.5).setup({weight = 0.9, splash = 90.0, mag_size = 6, reserve_mags = 5, reload_time = 2.5, spread_deg = 0.3, recoil = 3.0, ads_time = 0.2,
			recoil_pattern = [Vector2(1, 0)], upgrade_name = "Supernova Disruptor", color = Color(0.2, 0.85, 0.7)})
		"gloam": return WeaponDef.new("gloam", "Gloam Harp", 900, 0.45).setup({weight = 1.1, pierce = 6, mag_size = 10, reserve_mags = 6, reload_time = 2.2, spread_deg = 0.2, recoil = 2.5, ads_time = 0.22,
			recoil_pattern = [Vector2(1, 0)], upgrade_name = "Gloam Requiem", color = Color(0.35, 0.95, 0.85)})
		"reaper": return WeaponDef.new("reaper", "Hive Reaper", 130, 0.055).setup({weight = 2.6, mag_size = 500, reserve_mags = 1, reload_time = 6.5, automatic = true, spread_deg = 2.4, recoil = 0.7, ads_time = 0.55,
			spin_up = 0.9, recoil_pattern = [Vector2(1, 0.3), Vector2(0.8, -0.4), Vector2(1.1, 0.2)], upgrade_name = "Hive Sovereign", color = Color(0.3, 1.0, 0.55)})
	return null

## v7.12 alien LMG, sold only on the Sealed Annex pedestal (not in the crate).
const ALIEN := "reaper"
const ALIEN_PRICE := 8000
const ALIEN_AMMO := 4000
## Built from the three hidden parts (WonderQuest); never offered by the Mystery Crate.
const QUEST_WONDER := "gloam"

const ALL_IDS := ["sidearm", "scatter", "rifle", "cannon", "smg", "lmg", "nova"]
## The crate-only wonder weapon (original design: a resonance-field projector).
const WONDER := "nova"
## CC0 Quaternius models (see ASSETS.md) used for each weapon's viewmodel and wall-buy.
const MODELS := {"sidearm": "pistol", "scatter": "shotgun", "rifle": "rifle", "cannon": "launcher", "smg": "smg", "lmg": "lmg", "nova": "raygun", "gloam": "raygun", "reaper": "lmg"}
const STARTER := "sidearm"

## Wall-buy chalk outlines: weapon id -> price (500-1500). Buying it again while owned refills ammo at half price.
const WALL_PRICES := {"smg": 1000, "scatter": 1200, "rifle": 1400}

static func ammo_price(id: String) -> int:
	return int(WALL_PRICES.get(id, 0) / 2)

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
