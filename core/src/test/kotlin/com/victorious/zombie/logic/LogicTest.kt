package com.victorious.zombie.logic

import kotlin.random.Random
import kotlin.test.*

class RoundsTest {
    @Test fun round1Baseline() { assertEquals(6, Rounds.zombieCount(1)); assertEquals(100, Rounds.zombieHealth(1)) }
    @Test fun countIsMonotonic() { for (r in 1..60) assertTrue(Rounds.zombieCount(r + 1) >= Rounds.zombieCount(r)) }
    @Test fun countCapped() { assertEquals(120, Rounds.zombieCount(500)) }
    @Test fun healthLinearThenExponential() {
        assertEquals(500, Rounds.zombieHealth(9))
        assertEquals(550, Rounds.zombieHealth(10))
        assertTrue(Rounds.zombieHealth(20) > Rounds.zombieHealth(19))
    }
    @Test fun speedAndIntervalBounded() {
        assertEquals(150f, Rounds.zombieSpeed(100)); assertEquals(0.4f, Rounds.spawnInterval(100))
    }
    @Test fun invalidRoundRejected() { assertFailsWith<IllegalArgumentException> { Rounds.zombieCount(0) } }
}

class EconomyTest {
    @Test fun startsWith500() = assertEquals(500, Economy().points)
    @Test fun earning() {
        val e = Economy(0); e.onHit(); e.onKill(); e.onKill(headshot = true); e.onRepair()
        assertEquals(10 + 60 + 100 + 10, e.points)
    }
    @Test fun cannotOverspend() { val e = Economy(100); assertFalse(e.spend(101)); assertEquals(100, e.points) }
    @Test fun spendDeducts() { val e = Economy(1000); assertTrue(e.spend(950)); assertEquals(50, e.points) }
    @Test fun perkOnlyOnce() {
        val e = Economy(6000); val p = PerkMachine()
        assertTrue(p.buy(e)); assertFalse(p.buy(e)); assertEquals(3500, e.points)
    }
    @Test fun upgradeDoublesDamageOnce() {
        val e = Economy(10000); val u = UpgradeMachine()
        val up = u.upgrade(Weapons.STARTER, e)!!
        assertEquals(Weapons.STARTER.damage * 2, up.damage); assertNull(u.upgrade(up, e)); assertEquals(5000, e.points)
    }
}

class MysteryBoxTest {
    @Test fun probabilitiesSumToOne() {
        val b = MysteryBox(); assertEquals(1.0, b.table.sumOf { b.probabilityOf(it.first.id) }, 1e-9)
        assertEquals(0.05, b.probabilityOf("nova"), 1e-9)
    }
    @Test fun empiricalOddsMatchWeights() {
        val b = MysteryBox(); val rng = Random(42); val n = 100_000
        val counts = (1..n).groupingBy { b.roll(rng).id }.eachCount()
        for ((w, _) in b.table) assertEquals(b.probabilityOf(w.id), counts.getValue(w.id).toDouble() / n, 0.01)
    }
    @Test fun excludesCurrentWeapon() {
        val b = MysteryBox(); val rng = Random(1); repeat(1000) { assertNotEquals("smg", b.roll(rng, exclude = "smg").id) }
    }
    @Test fun buyRequiresPoints() {
        val b = MysteryBox(); assertNull(b.buy(Economy(900), Random(0)))
        val e = Economy(1000); assertNotNull(b.buy(e, Random(0))); assertEquals(50, e.points)
    }
}

class BarricadeTest {
    @Test fun startsFull() { val b = Barricade(); assertEquals(300, b.hp); assertEquals(6, b.planks); assertFalse(b.isBroken) }
    @Test fun damageClampsAtZero() { val b = Barricade(); b.damage(1000); assertEquals(0, b.hp); assertTrue(b.isBroken) }
    @Test fun partialPlank() { val b = Barricade(); b.damage(60); assertEquals(5, b.planks); assertEquals(240, b.hp) }
    @Test fun repairRestoresOnePlank() {
        val b = Barricade(); b.damage(300); assertTrue(b.repairPlank()); assertEquals(50, b.hp)
        b.damage(10); assertTrue(b.repairPlank()); assertEquals(50, b.hp)
    }
    @Test fun repairFullIsNoop() { assertFalse(Barricade().repairPlank()) }
}
