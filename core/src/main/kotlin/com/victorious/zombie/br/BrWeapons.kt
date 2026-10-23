package com.victorious.zombie.br

import kotlin.random.Random

enum class Rarity(val label: String, val damageMul: Float, val magMul: Float, val reloadMul: Float, val rateMul: Float) {
    COMMON("Common", 1f, 1f, 1f, 1f),
    RARE("Rare", 1.15f, 1.25f, 0.9f, 1f),
    EPIC("Epic", 1.3f, 1.5f, 0.8f, 0.9f),
}

/** Base stats of a gun at Common rarity. Original placeholder roster, tuned for fighter-vs-fighter fights. */
class BrGun(
    val id: String, val name: String,
    val damage: Float, val interval: Float, val mag: Int, val reload: Float,
    val bulletSpeed: Float, val range: Float, val spreadDeg: Float,
    val pellets: Int = 1, val pierce: Int = 0, val splash: Float = 0f,
)

object BrGuns {
    val SIDEARM = BrGun("sidearm", "Volt Sidearm", 14f, 0.30f, 12, 1.1f, 900f, 520f, 2f)
    val SMG = BrGun("smg", "Buzzsaw SMG", 8f, 0.075f, 32, 1.8f, 850f, 420f, 6f)
    val RIFLE = BrGun("rifle", "Pulse Rifle", 17f, 0.14f, 28, 2.0f, 1000f, 700f, 2.5f)
    val SCATTER = BrGun("scatter", "Scatterbolt", 7f, 0.85f, 5, 2.4f, 800f, 300f, 14f, pellets = 8)
    val LANCER = BrGun("lancer", "Rail Lancer", 70f, 1.05f, 4, 2.2f, 1600f, 1000f, 0.3f, pierce = 1)
    val NOVA = BrGun("nova", "Nova Disruptor", 55f, 1.3f, 3, 2.8f, 650f, 700f, 1f, splash = 80f)

    val ALL = listOf(SIDEARM, SMG, RIFLE, SCATTER, LANCER, NOVA)
    fun byId(id: String): BrGun? = ALL.firstOrNull { it.id == id }
    fun index(gun: BrGun): Int = ALL.indexOf(gun)
    fun at(index: Int): BrGun = ALL.getOrElse(index) { SIDEARM }
}

/** A gun at a rarity, with the derived numbers the sim uses. */
class BrWeapon(val gun: BrGun, val rarity: Rarity) {
    val name: String get() = gun.name
    val displayName: String get() = if (rarity == Rarity.COMMON) gun.name else "${rarity.label} ${gun.name}"
    val damage: Float get() = gun.damage * rarity.damageMul
    val interval: Float get() = gun.interval * rarity.rateMul
    val mag: Int get() = (gun.mag * rarity.magMul).toInt().coerceAtLeast(1)
    val reload: Float get() = gun.reload * rarity.reloadMul
    /** Theoretical damage per second with every shot landing. */
    val dps: Float get() = damage * gun.pellets / interval

    companion object { val START = BrWeapon(BrGuns.SIDEARM, Rarity.COMMON) }
}

/** Weighted loot rolls. Hot spots roll better rarities. */
object BrLoot {
    private val gunWeights = listOf(BrGuns.SMG to 26, BrGuns.RIFLE to 22, BrGuns.SCATTER to 22, BrGuns.LANCER to 9, BrGuns.NOVA to 6, BrGuns.SIDEARM to 15)
    private val rarityByTier = listOf(
        listOf(Rarity.COMMON to 70, Rarity.RARE to 27, Rarity.EPIC to 3),
        listOf(Rarity.COMMON to 45, Rarity.RARE to 42, Rarity.EPIC to 13),
        listOf(Rarity.COMMON to 20, Rarity.RARE to 50, Rarity.EPIC to 30),
    )

    private fun <T> pick(table: List<Pair<T, Int>>, rng: Random): T {
        var r = rng.nextInt(table.sumOf { it.second })
        for ((v, w) in table) { if (r < w) return v; r -= w }
        return table.last().first
    }

    fun rollWeapon(tier: Int, rng: Random): BrWeapon = BrWeapon(pick(gunWeights, rng), pick(rarityByTier[tier.coerceIn(0, 2)], rng))
    fun epicWeapon(rng: Random): BrWeapon = BrWeapon(pick(gunWeights.filter { it.first != BrGuns.SIDEARM }, rng), Rarity.EPIC)
}
