package com.victorious.zombie.fps

/**
 * Zombies 3D weapon table. All names are original placeholders. Damage is per bullet (per pellet for the shotgun);
 * zombie health starts at 150 (round 1) and grows each round, see [FpsRules.zombieHealth].
 */
class FpsGun(
    val id: String, val name: String,
    val damage: Float, val headMult: Float,
    /** Seconds between shots. Holding fire repeats at this rate for every gun. */
    val interval: Float,
    val mag: Int, val reserve: Int, val reload: Float,
    val pellets: Int = 1, val spreadDeg: Float = 0.6f, val range: Float = 60f,
    /** Extra zombies a bullet goes through. */
    val pierce: Int = 0,
    /** Blast radius at the impact point (0 = none). */
    val splash: Float = 0f,
    /** Wall price (0 = not on a wall). */
    val cost: Int = 0,
    val inBox: Boolean = true,
    /** Viewmodel shape: 0 pistol, 1 rifle, 2 shotgun, 3 smg, 4 lmg, 5 sniper, 6 wonder. */
    val shape: Int = 1,
)

/** A gun in the player's hands. Forged (upgraded) guns hit twice as hard and carry more ammo. */
class HeldGun(val gun: FpsGun, val forged: Boolean = false) {
    val damage get() = gun.damage * (if (forged) (if (gun.splash > 0f) 1.5f else 2f) else 1f)
    val magSize get() = if (forged) (gun.mag * 1.5f).toInt().coerceAtLeast(gun.mag + 1) else gun.mag
    val reserveMax get() = if (forged) gun.reserve * 2 else gun.reserve
    val name get() = if (forged) "Forged ${gun.name}" else gun.name
    var mag = magSize
    var reserve = reserveMax
    fun refill() { mag = magSize; reserve = reserveMax }
}

object FpsGuns {
    val PISTOL = FpsGun("p9", "P9 Sidearm", 60f, 2.5f, 0.17f, 8, 64, 1.5f, spreadDeg = 0.8f, inBox = false, shape = 0)
    val RANGER = FpsGun("ranger", "Ranger M1", 140f, 2.5f, 0.2f, 8, 96, 2.1f, spreadDeg = 0.3f, cost = 500, shape = 1)
    val TRENCH = FpsGun("trench", "Trench 12", 55f, 1.5f, 0.85f, 6, 48, 3.0f, pellets = 7, spreadDeg = 6f, range = 14f, cost = 500, shape = 2)
    val KESTREL = FpsGun("kestrel", "Kestrel SMG", 55f, 2f, 0.075f, 32, 192, 2.0f, spreadDeg = 2.2f, cost = 1000, shape = 3)
    val HARROW = FpsGun("harrow", "Harrow AR", 95f, 2.2f, 0.1f, 30, 180, 2.3f, spreadDeg = 1.4f, cost = 1200, shape = 1)
    val VULCAN = FpsGun("vulcan", "Vulcan LMG", 115f, 2f, 0.085f, 100, 400, 4.5f, spreadDeg = 2f, shape = 4)
    val SABRE = FpsGun("sabre", "Sabre .50", 650f, 3f, 1.0f, 5, 40, 3.0f, spreadDeg = 0f, pierce = 3, shape = 5)
    val THUNDER = FpsGun("thunder", "Thunder Ray", 1600f, 1f, 0.45f, 2, 40, 2.4f, spreadDeg = 0f, splash = 2.6f, shape = 6)

    val ALL = listOf(PISTOL, RANGER, TRENCH, KESTREL, HARROW, VULCAN, SABRE, THUNDER)
    val BOX = ALL.filter { it.inBox }
    fun byId(id: String) = ALL.firstOrNull { it.id == id }
}

enum class Perk(val title: String, val cost: Int, val needsPower: Boolean, val r: Float, val g: Float, val b: Float, val letter: String) {
    IRONHIDE("Ironhide", 2500, true, 0.9f, 0.15f, 0.1f, "I"),
    QUICKHAND("Quickhand", 3000, true, 0.2f, 0.9f, 0.3f, "Q"),
    RAPIDFIRE("Rapidfire", 2000, true, 1f, 0.75f, 0.1f, "R"),
    SECOND_WIND("Second Wind", 500, false, 0.3f, 0.6f, 1f, "S"),
}

enum class PowerUp(val title: String, val r: Float, val g: Float, val b: Float) {
    MAX_AMMO("Max Ammo", 0.3f, 1f, 0.3f), INSTA_KILL("Insta-Kill", 1f, 1f, 1f), DOUBLE_POINTS("Double Points", 1f, 0.85f, 0.1f),
    NUKE("Nuke", 1f, 0.45f, 0.1f), CARPENTER("Carpenter", 0.7f, 0.45f, 0.2f),
}

/** Round and economy numbers in one place (tests check them). */
object FpsRules {
    const val START_POINTS = 500
    const val HIT_POINTS = 10; const val KILL_POINTS = 60; const val HEADSHOT_KILL_POINTS = 100; const val KNIFE_KILL_POINTS = 130
    const val BOARD_POINTS = 10; const val BOARD_POINTS_CAP = 500
    const val NUKE_POINTS = 400; const val CARPENTER_POINTS = 200
    const val BOX_COST = 950; const val FORGE_COST = 5000; const val REFORGE_COST = 2500
    const val MAX_ALIVE = 24
    const val ROUND_BREAK = 10f; const val FIRST_ROUND_DELAY = 3f
    const val PLAYER_HP = 100f; const val IRONHIDE_HP = 250f
    const val ZOMBIE_HIT = 50f
    const val KNIFE_DAMAGE = 150f; const val KNIFE_RANGE = 1.7f; const val KNIFE_INTERVAL = 0.65f
    const val POWERUP_TIME = 30f; const val POWERUP_LIFE = 25f; const val POWERUP_CHANCE = 0.03f; const val POWERUPS_PER_ROUND = 4
    const val SECOND_WIND_USES = 3

    /** Zombie health: 150 at round 1, +100 per round to round 9, then +10% per round. */
    fun zombieHealth(round: Int): Float = if (round < 10) 150f + 100f * (round - 1) else 950f * Math.pow(1.1, (round - 9).toDouble()).toFloat()

    /** Zombies in a round (solo). */
    fun zombieCount(round: Int): Int = when (round) { 1 -> 6; 2 -> 8; 3 -> 13; 4 -> 18; 5 -> 24; else -> (24 + (round - 5) * 4).coerceAtMost(90) }

    /** Seconds between spawns. */
    fun spawnInterval(round: Int): Float = (2.2f * Math.pow(0.93, (round - 1).toDouble()).toFloat()).coerceAtLeast(0.45f)

    /** Share of joggers and runners; the rest walk. */
    fun jogShare(round: Int) = ((round - 1) * 0.22f).coerceIn(0f, 1f)
    fun runShare(round: Int) = ((round - 4) * 0.12f).coerceIn(0f, 0.8f)

    /** Seconds per board a zombie needs to tear one off. */
    fun tearTime(round: Int) = (1.4f - round * 0.05f).coerceAtLeast(0.6f)
}
