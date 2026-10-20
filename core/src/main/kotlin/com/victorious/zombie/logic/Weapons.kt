package com.victorious.zombie.logic

import kotlin.random.Random

/** Original weapon roster (placeholder names, no third-party IP). */
data class Weapon(
    val id: String,
    val name: String,
    val damage: Int,
    val fireInterval: Float,
    val bulletSpeed: Float = 700f,
    val pellets: Int = 1,
    val upgraded: Boolean = false,
) {
    fun upgradedVersion(): Weapon =
        if (upgraded) this else copy(name = "$name Mk.II", damage = damage * 2, fireInterval = fireInterval * 0.8f, upgraded = true)
}

object Weapons {
    val STARTER = Weapon("sidearm", "Volt Sidearm", 30, 0.35f)
    val SCATTER = Weapon("scatter", "Scatterbolt", 25, 0.8f, pellets = 5)
    val RIFLE = Weapon("rifle", "Pulse Rifle", 40, 0.12f)
    val CANNON = Weapon("cannon", "Rail Lancer", 200, 0.9f, bulletSpeed = 1100f)
    val SMG = Weapon("smg", "Buzzsaw SMG", 22, 0.07f)
    val NOVA = Weapon("nova", "Nova Disruptor", 400, 0.6f, bulletSpeed = 500f)
}

/** Mystery weapon box: weighted random weapon for a point cost. */
class MysteryBox(
    val cost: Int = COST,
    val table: List<Pair<Weapon, Int>> = DEFAULT_TABLE,
) {
    init { require(table.isNotEmpty() && table.all { it.second > 0 }) }

    val totalWeight: Int get() = table.sumOf { it.second }

    fun probabilityOf(weaponId: String): Double =
        table.filter { it.first.id == weaponId }.sumOf { it.second }.toDouble() / totalWeight

    fun roll(rng: Random, exclude: String? = null): Weapon {
        val pool = table.filter { it.first.id != exclude }.ifEmpty { table }
        var r = rng.nextInt(pool.sumOf { it.second })
        for ((w, weight) in pool) {
            if (r < weight) return w
            r -= weight
        }
        return pool.last().first
    }

    /** Spend points and roll; null if unaffordable. */
    fun buy(economy: Economy, rng: Random, current: String? = null): Weapon? =
        if (economy.spend(cost)) roll(rng, current) else null

    companion object {
        const val COST = 950
        val DEFAULT_TABLE = listOf(
            Weapons.SCATTER to 30,
            Weapons.SMG to 30,
            Weapons.RIFLE to 25,
            Weapons.CANNON to 10,
            Weapons.NOVA to 5,
        )
    }
}
