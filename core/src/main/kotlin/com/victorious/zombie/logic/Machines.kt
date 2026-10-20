package com.victorious.zombie.logic

/** One perk: "Iron Hide" doubles max health. */
class PerkMachine(val name: String = "Iron Hide Tonic", val cost: Int = 2500) {
    var owned = false
        private set
    fun buy(economy: Economy): Boolean {
        if (owned || !economy.spend(cost)) return false
        owned = true
        return true
    }
}

/** Weapon upgrade machine ("Overcharge Forge"). */
class UpgradeMachine(val name: String = "Overcharge Forge", val cost: Int = 5000) {
    fun upgrade(weapon: Weapon, economy: Economy): Weapon? {
        if (weapon.upgraded || !economy.spend(cost)) return null
        return weapon.upgradedVersion()
    }
}
