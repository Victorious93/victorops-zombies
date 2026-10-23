package com.victorious.zombie.br

import com.victorious.zombie.logic.Characters
import com.victorious.zombie.net.ClientSession
import com.victorious.zombie.net.HostSession
import com.victorious.zombie.net.LoopbackLink
import com.victorious.zombie.sim.PlayerInput
import kotlin.math.hypot
import kotlin.random.Random
import kotlin.test.*

private const val DT = 1 / 30f

/**
 * Humans only, no bots, match started and past the deploy countdown, protection switched off. A match with a single
 * fighter ends at once, so a lone human gets an invulnerable parked dummy (id 9) as company.
 */
private fun liveWorld(vararg chars: String, seed: Long = 5): BrWorld {
    val w = BrWorld(seed, autoStartS = 0f, withBots = false)
    chars.forEachIndexed { i, c -> assertTrue(w.join(i, c)) }
    if (chars.size == 1) assertTrue(w.join(9, "martha"))
    w.startMatch()
    w.loot.clear()
    repeat((BrWorld.DEPLOY_TIME / DT).toInt() + 2) { w.update(DT) }
    assertEquals(Phase.LIVE, w.phase)
    for (f in w.fighters.values) f.protectedT = 0f
    w.fighters[9]?.let { it.protectedT = 1e9f; it.x = 60f; it.y = 60f }
    return w
}

private fun BrWorld.place(id: Int, x: Float, y: Float) { fighters.getValue(id).apply { this.x = x; this.y = y } }
private fun BrWorld.run(seconds: Float) { repeat((seconds / DT).toInt()) { update(DT) } }

/** Open ground (no wall within 110) close to the middle of the map, found by scanning rings outward. */
private fun BrWorld.openSpot(): Pair<Float, Float> {
    for (r in 0..1000 step 50) for (k in 0 until 24) {
        val a = k * 2 * Math.PI.toFloat() / 24
        val x = BrConst.CENTER + kotlin.math.cos(a) * r; val y = BrConst.CENTER + kotlin.math.sin(a) * r
        if (map.isFree(x, y, 110f)) return x to y
    }
    error("no open spot")
}

class BrMapTest {
    @Test fun sameSeedSameMap() {
        val a = BrMap(42); val b = BrMap(42)
        assertEquals(a.walls.size, b.walls.size)
        a.walls.zip(b.walls).forEach { (p, q) -> assertTrue(p.x == q.x && p.y == q.y && p.w == q.w && p.h == q.h) }
        assertEquals(a.lootSpots.size, b.lootSpots.size)
        assertEquals(a.spawnPoints.map { it.x }, b.spawnPoints.map { it.x })
        assertNotEquals(a.walls.size to a.walls.first().x, BrMap(43).let { it.walls.size to it.walls.first().x })
    }

    @Test fun manySeedsGenerateSoundMaps() {
        for (seed in 1..60) {
            val m = BrMap(seed)
            assertTrue(m.walls.size in 60..260, "seed $seed: ${m.walls.size} walls")
            m.walls.forEach { w ->
                assertTrue(w.w >= 2f && w.h >= 2f, "seed $seed: degenerate wall ${w.w}x${w.h}")
                assertTrue(w.x >= 0f && w.y >= 0f && w.x2 <= BrConst.SIZE && w.y2 <= BrConst.SIZE, "seed $seed: wall outside the map")
            }
            assertEquals(BrConst.FIELD, m.spawnPoints.size)
            m.spawnPoints.forEach { assertTrue(m.isFree(it.x, it.y, BrConst.BODY_R), "seed $seed: spawn in a wall") }
            m.lootSpots.forEach { assertTrue(m.isFree(it.x, it.y, 10f), "seed $seed: loot in a wall") }
            assertTrue(m.lootSpots.count { it.tier == 0 } >= 12, "seed $seed: too few outskirts spots")
            assertTrue(m.lootSpots.size >= 40)
        }
    }

    @Test fun everySpawnAndEveryLootSpotIsReachableFromEverySpawn() {
        for (seed in 1..60) {
            val m = BrMap(seed)
            val s0 = m.spawnPoints[0]
            for (p in m.spawnPoints.drop(1)) assertNotNull(m.nav.path(s0.x, s0.y, p.x, p.y), "seed $seed: spawns are cut off from each other")
            for (l in m.lootSpots) assertNotNull(m.nav.path(s0.x, s0.y, l.x, l.y), "seed $seed: loot (${l.x.toInt()},${l.y.toInt()}) tier ${l.tier} is sealed off")
        }
    }

    @Test fun buildingsAlwaysLeaveALaneBetweenThem() {
        // every doorway must lead somewhere a body can stand: probe the point 40 px outside each gap in a building wall
        for (seed in 1..60) {
            val m = BrMap(seed)
            for (l in m.lootSpots.filter { it.tier > 0 }) {
                val out = m.nav.path(l.x, l.y, BrConst.CENTER + 400f, BrConst.CENTER + 400f)
                assertNotNull(out, "seed $seed: building loot (${l.x.toInt()},${l.y.toInt()}) has no way out")
            }
        }
    }

    @Test fun pathsAvoidWallsAndEndAtTheGoal() {
        val m = BrMap(7); val rnd = Random(1)
        repeat(60) {
            val a = m.nearestFree(rnd.nextFloat() * 2000f + 200f, rnd.nextFloat() * 2000f + 200f, 20f)
            val b = m.nearestFree(rnd.nextFloat() * 2000f + 200f, rnd.nextFloat() * 2000f + 200f, 20f)
            if (!m.nav.isWalkable(a.x, a.y) || !m.nav.isWalkable(b.x, b.y)) return@repeat
            val p = m.nav.path(a.x, a.y, b.x, b.y) ?: return@repeat
            var cx = a.x; var cy = a.y
            for (w in p) { assertTrue(m.clearLine(cx, cy, w.x, w.y, BrConst.BODY_R - 2f), "leg crosses a wall"); cx = w.x; cy = w.y }
            assertTrue(hypot(cx - b.x, cy - b.y) < 30f, "path stops ${hypot(cx - b.x, cy - b.y)} short of the goal")
        }
    }

    @Test fun resolvePushesBodiesOutOfWallsAndKeepsThemInside() {
        val m = BrMap(3); val out = FloatArray(2)
        val w = m.walls.first()
        m.resolve(w.x + w.w / 2, w.y + w.h / 2, BrConst.BODY_R, out)
        assertTrue(m.isFree(out[0], out[1], BrConst.BODY_R - 0.5f), "still overlapping after resolve")
        m.resolve(-50f, 99999f, BrConst.BODY_R, out)
        assertTrue(out[0] >= BrConst.BODY_R && out[1] <= BrConst.SIZE - BrConst.BODY_R)
    }
}

class GeoTest {
    @Test fun segmentVersusRect() {
        val r = Rect(10f, 10f, 10f, 10f)
        assertEquals(0.5f, Geo.segRectT(0f, 15f, 20f, 15f, r) * 2f * 0.5f + 0f, 0.26f) // enters at x=10 => t=0.5 of a 0..20 run
        assertEquals(-1f, Geo.segRectT(0f, 0f, 20f, 5f, r))
        assertEquals(0f, Geo.segRectT(15f, 15f, 30f, 15f, r)) // starts inside
        assertEquals(-1f, Geo.segRectT(0f, 15f, 5f, 15f, r)) // stops short
    }

    @Test fun segmentVersusCircle() {
        assertEquals(0f, Geo.segCircleT(0f, 0f, 10f, 0f, 1f, 0f, 5f))
        val t = Geo.segCircleT(0f, 0f, 100f, 0f, 50f, 0f, 10f)
        assertEquals(0.4f, t, 0.001f)
        assertEquals(-1f, Geo.segCircleT(0f, 0f, 100f, 0f, 50f, 30f, 10f))
        assertEquals(-1f, Geo.segCircleT(0f, 0f, 30f, 0f, 50f, 0f, 10f))
    }
}

class BrWeaponTest {
    @Test fun rarityImprovesEveryGun() {
        for (g in BrGuns.ALL) {
            val c = BrWeapon(g, Rarity.COMMON); val r = BrWeapon(g, Rarity.RARE); val e = BrWeapon(g, Rarity.EPIC)
            assertTrue(c.dps < r.dps && r.dps < e.dps, "${g.id}: dps must rise with rarity")
            assertTrue(c.mag <= r.mag && r.mag <= e.mag)
            assertTrue(c.reload >= r.reload && r.reload >= e.reload)
        }
    }

    @Test fun gunsStayInABalancedBand() {
        val dps = BrGuns.ALL.associate { it.id to BrWeapon(it, Rarity.COMMON).dps }
        assertTrue(dps.values.all { it in 35f..140f }, "dps outside the band: $dps")
        assertTrue("sidearm" in dps.entries.sortedBy { it.value }.take(2).map { it.key }, "the start gun should be among the two weakest: $dps")
        // no gun may delete a fresh fighter (100 HP) in one trigger pull at Epic
        for (g in BrGuns.ALL) assertTrue(BrWeapon(g, Rarity.EPIC).damage * g.pellets < 100f, "${g.id} one-shots")
    }

    @Test fun lootRollsRespectTierAndEpicDropsAreEpic() {
        val rng = Random(9)
        fun share(tier: Int) = (1..4000).count { BrLoot.rollWeapon(tier, rng).rarity == Rarity.EPIC } / 4000f
        assertTrue(share(0) < share(1) && share(1) < share(2), "hot spots must roll better loot")
        repeat(200) { val w = BrLoot.epicWeapon(rng); assertEquals(Rarity.EPIC, w.rarity); assertNotEquals(BrGuns.SIDEARM, w.gun) }
    }
}

class BrZoneTest {
    @Test fun everyNextCircleIsInsideTheCurrentOneAndShrinksSmoothly() {
        for (seed in 1L..12L) {
            val w = BrWorld(seed, autoStartS = 0f, withBots = false)
            w.join(0, "snoop"); w.join(1, "martha"); w.startMatch()
            var lastR = w.zoneR; var stages = 0; var lastIdx = w.zoneIdx
            repeat(30 * 400) {
                w.fighters.values.forEach { it.protectedT = 99f } // keep both alive so the match runs through every stage
                w.update(DT)
                if (w.phase == Phase.LIVE) {
                    assertTrue(w.zoneR <= lastR + 0.01f, "seed $seed: zone grew")
                    lastR = w.zoneR
                    if (w.zoneIdx < BrWorld.ZONES.size) assertTrue(hypot(w.nextCx - w.zoneCx, w.nextCy - w.zoneCy) + w.nextR <= w.zoneR + 1f, "seed $seed stage ${w.zoneIdx}: next circle sticks out")
                    if (w.zoneIdx != lastIdx) { stages++; lastIdx = w.zoneIdx }
                }
            }
            assertEquals(BrWorld.ZONES.size, stages, "seed $seed: not every stage ran")
            assertEquals(0f, w.zoneR, 0.5f)
        }
    }

    @Test fun zoneDamageIgnoresShieldAndHurts() {
        val w = liveWorld("snoop", "martha")
        // let the first shrink finish so there is real ground outside the circle (everyone stays protected meanwhile)
        repeat(30 * 90) { w.fighters.values.forEach { it.protectedT = 99f }; w.update(DT) }
        assertTrue(w.zoneIdx >= 1, "first shrink should be done by now (zoneIdx=${w.zoneIdx})")
        val f = w.fighters.getValue(1)
        var spot: Pair<Float, Float>? = null
        for (k in 0 until 72) {
            val a = k * 2 * Math.PI.toFloat() / 72
            val x = w.zoneCx + kotlin.math.cos(a) * (w.zoneR + 120f); val y = w.zoneCy + kotlin.math.sin(a) * (w.zoneR + 120f)
            if (w.map.isFree(x, y, 20f) && !w.inZone(x, y)) { spot = x to y; break }
        }
        assertNotNull(spot, "no ground outside the zone to test with")
        f.protectedT = 0f; f.x = spot.first; f.y = spot.second; f.shield = 100f; f.hp = f.maxHp
        w.fighters.getValue(0).protectedT = 99f
        w.run(2f)
        assertTrue(f.hp < f.maxHp - 1f, "zone damage must hit health (hp=${f.hp})")
        assertEquals(100f, f.shield, "zone damage must not touch shield")
    }
}

class BrCombatTest {
    @Test fun lobbyJoinRulesAndHostStart() {
        val w = BrWorld(1, autoStartS = 60f, withBots = false)
        assertTrue(w.join(0, "snoop")); assertFalse(w.join(0, "martha")); assertTrue(w.join(1, "martha")); assertTrue(w.join(2, "snoop")); assertTrue(w.join(3, "snoop"))
        assertFalse(w.join(4, "snoop"), "fifth human")
        assertFalse(w.join(BrWorld.BOT_ID_BASE, "snoop"), "bot id range is reserved")
        w.applyInput(0, PlayerInput(use = true)); w.update(DT)
        assertEquals(Phase.DEPLOY, w.phase)
        assertFalse(w.join(9, "snoop"), "no joining once the match started")
    }

    @Test fun soloLobbyStartsByItselfAndFillsWithBots() {
        val w = BrWorld(1, autoStartS = 1.5f)
        w.join(0, "snoop")
        w.run(2f)
        assertEquals(Phase.DEPLOY, w.phase)
        assertEquals(BrConst.FIELD, w.fighters.size)
        assertEquals(1, w.humans().size)
        assertTrue(w.fighters.values.all { it.protectedT > 0f }, "everyone is protected while dropping in")
    }

    @Test fun deployFreezesAndThenGoes() {
        val w = BrWorld(1, autoStartS = 0f, withBots = false); w.join(0, "snoop"); w.join(1, "martha"); w.startMatch()
        val f = w.fighters.getValue(0); val x0 = f.x
        w.applyInput(0, PlayerInput(dx = 1f)); w.run(2f)
        assertEquals(x0, f.x, "no movement while dropping in")
        w.run(4f); assertEquals(Phase.LIVE, w.phase)
        w.fighters.values.forEach { it.protectedT = 0f }
        w.run(1f); assertTrue(f.x != x0)
    }

    @Test fun bulletsHurtShieldFirstAndOwnerIsImmune() {
        val w = liveWorld("snoop", "martha")
        val (x, y) = w.openSpot(); w.place(0, x, y); w.place(1, x + 150, y)
        val a = w.fighters.getValue(0); val b = w.fighters.getValue(1)
        b.shield = 30f
        w.applyInput(0, PlayerInput(aimX = 1f, aimY = 0f, fire = true))
        w.run(1.2f)
        assertTrue(b.shield < 30f, "shield absorbs first")
        assertTrue(b.hp < b.maxHp || b.shield == 0f)
        assertEquals(a.maxHp, a.hp, "shooter untouched")
        assertTrue(a.rounds < a.weapon.mag, "shots use ammo")
    }

    @Test fun wallsStopBullets() {
        val w = liveWorld("snoop", "martha")
        val wall = w.map.walls.first { it.w > 40f && it.h > 40f && w.map.isFree(it.x - 120f, it.y + it.h / 2, 20f) && w.map.isFree(it.x2 + 120f, it.y + it.h / 2, 20f) }
        val y = wall.y + wall.h / 2
        w.place(0, wall.x - 100f, y); w.place(1, wall.x2 + 100f, y)
        val b = w.fighters.getValue(1)
        w.applyInput(0, PlayerInput(aimX = 1f, fire = true)); w.run(1.5f)
        assertEquals(b.maxHp, b.hp, "bullets must not pass through walls")
        assertEquals(0f, b.shield)
    }

    @Test fun killsAwardPlacementAndTheLastFighterWins() {
        val w = liveWorld("snoop", "martha")
        val (x, y) = w.openSpot(); w.place(0, x, y); w.place(1, x + 120, y)
        val a = w.fighters.getValue(0); val b = w.fighters.getValue(1)
        b.hp = 1f; a.weapon = BrWeapon(BrGuns.RIFLE, Rarity.EPIC); a.rounds = a.weapon.mag
        w.applyInput(0, PlayerInput(aimX = 1f, fire = true)); w.run(1f)
        assertFalse(b.alive); assertEquals(2, b.placement); assertEquals(1, a.kills)
        assertEquals(Phase.ENDED, w.phase); assertEquals(0, w.winnerId); assertEquals(1, a.placement)
        val snap = w.snapshot(0)
        assertTrue(snap.feed.any { it.contains("eliminated") }, "kill feed: ${snap.feed}")
        // death drops the gun (non-starter) and a shield cell
        assertTrue(w.loot.any { it.kind == LootKind.CELL })
    }

    @Test fun rematchGoesBackToTheLobbyWithTheSameHumans() {
        val w = liveWorld("snoop", "martha")
        w.fighters.getValue(1).hp = 0.5f; w.fighters.getValue(1).let { w.damage(it, 5f, 0, "test") }
        w.update(DT)
        assertEquals(Phase.ENDED, w.phase)
        w.run(3.5f)
        w.applyInput(0, PlayerInput(use = true)); w.update(DT)
        assertEquals(Phase.LOBBY, w.phase); assertEquals(2, w.fighters.size)
        assertTrue(w.fighters.values.all { it.alive && it.hp == it.maxHp })
    }

    @Test fun reloadRefillsAndAutoReloadsWhenEmpty() {
        val w = liveWorld("snoop")
        val f = w.fighters.getValue(0); f.weapon = BrWeapon.START; f.rounds = 3
        w.applyInput(0, PlayerInput(reload = true)); w.update(DT)
        assertTrue(f.reloading)
        w.applyInput(0, PlayerInput()); w.run(2f)
        assertFalse(f.reloading); assertEquals(f.weapon.mag, f.rounds)
        f.rounds = 1; val (x, y) = w.openSpot(); w.place(0, x, y)
        w.applyInput(0, PlayerInput(aimX = 1f, fire = true)); w.run(0.5f)
        assertTrue(f.reloading || f.rounds > 1, "an empty magazine starts a reload")
    }

    @Test fun pierceHitsTwoInALine() {
        val w = liveWorld("snoop", "martha", "snoop")
        val (x, y) = w.openSpot(); w.place(0, x, y); w.place(1, x + 150, y); w.place(2, x + 260, y)
        val a = w.fighters.getValue(0); a.weapon = BrWeapon(BrGuns.LANCER, Rarity.COMMON); a.rounds = 4
        w.applyInput(0, PlayerInput(aimX = 1f, fire = true)); w.run(0.4f)
        w.applyInput(0, PlayerInput())
        assertTrue(w.fighters.getValue(1).hp < w.fighters.getValue(1).maxHp && w.fighters.getValue(2).hp < w.fighters.getValue(2).maxHp, "lancer should pierce into the second target")
    }

    @Test fun novaSplashHurtsNeighboursButNotTheShooter() {
        val w = liveWorld("snoop", "martha", "snoop")
        val (x, y) = w.openSpot(); w.place(0, x, y); w.place(1, x + 200, y); w.place(2, x + 200, y + 40)
        val a = w.fighters.getValue(0); a.weapon = BrWeapon(BrGuns.NOVA, Rarity.COMMON); a.rounds = 3
        w.applyInput(0, PlayerInput(aimX = 1f, fire = true)); w.run(0.7f)
        w.applyInput(0, PlayerInput())
        assertTrue(w.fighters.getValue(1).hp < w.fighters.getValue(1).maxHp); assertTrue(w.fighters.getValue(2).hp < w.fighters.getValue(2).maxHp, "splash reaches the neighbour")
        assertEquals(a.maxHp, a.hp)
    }
}

class BrLootTest {
    @Test fun weaponsSwapOnUseAndOldGunDrops() {
        val w = liveWorld("snoop")
        val f = w.fighters.getValue(0); val (x, y) = w.openSpot(); w.place(0, x, y)
        f.weapon = BrWeapon(BrGuns.SMG, Rarity.RARE)
        w.loot += Loot(900, LootKind.WEAPON, x + 10f, y, BrWeapon(BrGuns.RIFLE, Rarity.EPIC))
        assertTrue(w.snapshot(0).self!!.prompt.contains("Epic Pulse Rifle"))
        w.applyInput(0, PlayerInput(use = true)); w.update(DT)
        assertEquals(BrGuns.RIFLE, f.weapon.gun); assertEquals(f.weapon.mag, f.rounds)
        assertTrue(w.loot.any { it.weapon?.gun == BrGuns.SMG }, "old gun lands on the floor")
        assertFalse(w.loot.any { it.id == 900 })
    }

    @Test fun healsAutoPickUpToTheCarryLimit() {
        val w = liveWorld("snoop")
        val f = w.fighters.getValue(0); val (x, y) = w.openSpot(); w.place(0, x, y)
        repeat(5) { w.loot += Loot(800 + it, LootKind.MEDKIT, x + it, y, null) }
        w.update(DT); w.update(DT)
        assertEquals(BrWorld.CARRY, f.medkits); assertEquals(2, w.loot.count { it.kind == LootKind.MEDKIT })
    }

    @Test fun healChannelCompletesAndIsInterruptedByDamage() {
        val w = liveWorld("snoop", "martha")
        val f = w.fighters.getValue(0); f.hp = 40f; f.medkits = 1
        val (x, y) = w.openSpot(); w.place(0, x, y); w.place(1, x + 900, y)
        w.applyInput(0, PlayerInput(heal = true)); w.run(1f)
        assertTrue(f.healKind == 1 && f.healT > 0.5f)
        w.damage(f, 5f, 1, "test")
        assertEquals(0, f.healKind, "damage interrupts")
        assertEquals(1, f.medkits, "an interrupted heal is not consumed")
        w.run(BrWorld.MEDKIT_TIME + 0.5f)
        assertEquals(0, f.medkits); assertTrue(f.hp >= 85f - 0.5f, "hp ${f.hp}")
    }

    @Test fun shieldCellsAndNoWasteWhenFull() {
        val w = liveWorld("snoop")
        val f = w.fighters.getValue(0); f.cells = 2; f.shield = 80f; f.medkits = 0
        w.applyInput(0, PlayerInput(heal = true)); w.run(2.5f)
        assertEquals(100f, f.shield, 0.01f); assertEquals(1, f.cells)
        w.run(2.5f)
        assertEquals(1, f.cells, "no wasted cell at full shield")
    }

    @Test fun abilitiesDoWhatTheyPromise() {
        val w = liveWorld("snoop", "martha")
        val (x, y) = w.openSpot(); w.place(0, x, y); w.place(1, x + 100, y)
        val snoop = w.fighters.getValue(0); val martha = w.fighters.getValue(1)
        w.applyInput(0, PlayerInput(ability = true)); w.run(0.5f)
        assertTrue(martha.x > x + 100f + 30f, "Bass Drop knocks back (moved ${martha.x - x - 100f})")
        assertTrue(martha.hp < martha.maxHp)
        assertTrue(snoop.abilityCd > 20f)
        w.applyInput(1, PlayerInput(ability = true)); w.update(DT)
        assertTrue(martha.shield >= 34f); assertTrue(martha.reduceT > 0f)
    }

    @Test fun hordeBitesAndCanBeShot() {
        val w = liveWorld("snoop")
        val f = w.fighters.getValue(0); val (x, y) = w.openSpot(); w.place(0, x, y)
        w.zombies += Zomb(777, x + 20f, y, BrWorld.ZOMBIE_HP)
        w.run(1f)
        assertTrue(f.hp < f.maxHp, "zombie contact hurts")
        f.hp = f.maxHp
        w.zombies.clear(); w.zombies += Zomb(778, x + 200f, y, 20f)
        w.applyInput(0, PlayerInput(aimX = 1f, fire = true)); w.run(0.8f)
        assertTrue(w.zombies.isEmpty(), "zombie shot dead")
    }
}

class BrNetTest {
    private fun sample(): BrSnapshot {
        val w = liveWorld("snoop", "martha")
        val (x, y) = w.openSpot(); w.place(0, x, y); w.place(1, x + 100, y)
        w.zombies += Zomb(1, x + 50, y + 50, 60f); w.loot += Loot(1, LootKind.WEAPON, x, y + 30, BrWeapon(BrGuns.LANCER, Rarity.EPIC))
        w.applyInput(0, PlayerInput(aimX = 1f, fire = true)); w.run(0.3f)
        return w.snapshot(1)
    }

    @Test fun codecRoundTrips() {
        val s = sample(); val d = BrCodec.fromText(BrCodec.toText(s))
        assertEquals(s.seed, d.seed); assertEquals(s.phase, d.phase); assertEquals(s.alive, d.alive); assertEquals(s.meId, d.meId)
        assertEquals(s.fighters.size, d.fighters.size); assertEquals(s.zombies.size, d.zombies.size); assertEquals(s.bullets.size, d.bullets.size); assertEquals(s.loot.size, d.loot.size)
        val me = d.fighters.first { it.id == 1 }; assertEquals("martha", me.characterId); assertEquals(BrWorld.BASE_HP + 15f, me.maxHp)
        assertEquals(s.fighters.first { it.id == 1 }.x, me.x, 0.05f)
        assertEquals(BrGuns.LANCER.id, BrGuns.at(d.loot.first().gunIndex).id); assertEquals(2, d.loot.first().rarity)
        assertEquals(s.zone.r, d.zone.r); assertEquals(s.self!!.medkits, d.self!!.medkits)
        assertEquals(s.feed, d.feed)
    }

    @Test fun noFocusSurvivesTheWire() {
        val w = BrWorld(1, autoStartS = 60f, withBots = false); w.join(0, "snoop")
        val d = BrCodec.decode(BrCodec.encode(w.snapshot(77))) // unknown viewer
        assertEquals(-1, d.focusId); assertNull(d.self)
    }

    @Test fun fullMatchSnapshotsStaySmall() {
        val w = BrWorld(3, autoStartS = 0f)
        w.join(0, "snoop"); w.run(2f)
        var biggest = 0
        repeat(30 * 120) { w.update(DT); if (it % 15 == 0) biggest = maxOf(biggest, BrCodec.encode(w.snapshot(0)).size) }
        println("BR biggest snapshot: $biggest bytes")
        assertTrue(biggest < 6000, "snapshot of $biggest bytes is too big for ~15 Hz on Bluetooth-class links")
    }

    @Test fun garbageIsRejectedNotCrashing() {
        val good = BrCodec.encode(sample())
        assertFails { BrCodec.decode(ByteArray(0)) }
        assertFails { BrCodec.decode(good.copyOf(good.size / 2)) }
        val rnd = Random(4)
        repeat(300) { runCatching { BrCodec.decode(ByteArray(rnd.nextInt(1, 300)) { rnd.nextInt().toByte() }) } } // must throw cleanly or decode, never hang or OOM
    }

    @Test fun extendedInputRoundTripsAndOldFormatStillParses() {
        val i = PlayerInput(0.5f, -1f, true, false, 0.6f, -0.8f, true, true, false)
        assertEquals(i, PlayerInput.fromText(i.toText()))
        assertEquals(4, PlayerInput(0.5f, -1f, true, false).toText().split(',').size, "no extras: stays wire-compatible")
        assertEquals(PlayerInput(1f, -1f, false, false), PlayerInput.fromText("900,-900,0,0"))
        assertNull(PlayerInput.fromText("1,2,3,4,5")); assertNull(PlayerInput.fromText("1,2,3,4,x,6,7"))
        assertEquals(PlayerInput(aimX = 1f, aimY = 1f, reload = true), PlayerInput.fromText("0,0,0,0,999,999,4"))
    }

    @Test fun royaleOverTheSessionLayer() {
        val host = HostSession.createRoyale(Characters.SNOOP, autoStartS = 60f)
        val (a, b) = LoopbackLink.pair()
        host.attach(a)
        val client = ClientSession(b, "martha")
        host.tick(0.05f)
        assertEquals(1, client.playerId); assertEquals("royale", client.kind)
        repeat(10) { host.tick(0.07f) }
        val lobby = client.latestRoyale; assertNotNull(lobby)
        assertEquals(Phase.LOBBY.ordinal, lobby.phase); assertEquals(listOf("Snoop", "Martha"), lobby.lobby)
        host.sim.applyInput(0, PlayerInput(use = true)); host.tick(0.05f)
        repeat(160) { client.tick(0.05f, PlayerInput(dx = 1f, aimX = 1f, fire = true)); host.tick(0.05f) }
        val live = client.latestRoyale!!
        assertEquals(Phase.LIVE.ordinal, live.phase); assertEquals(BrConst.FIELD, live.field)
        assertEquals(1, live.meId); assertTrue(live.fighters.any { it.id == 1 })
        // a late joiner is told the match is full/started
        val (c, d) = LoopbackLink.pair(); host.attach(c); val late = ClientSession(d, "snoop"); host.tick(0.05f)
        assertTrue(late.rejected)
        client.close(); host.tick(0.05f)
        assertFalse(host.sim.hasPlayer(1))
    }

    @Test fun zombieSurvivalWelcomeIsUnchanged() {
        val host = HostSession.create(Characters.SNOOP)
        val (a, b) = LoopbackLink.pair(); host.attach(a)
        val client = ClientSession(b, "martha"); host.tick(0.05f)
        assertEquals(1, client.playerId); assertNull(client.kind)
    }
}

class BrBotMatchTest {
    private class Stats(val world: BrWorld, val firstKill: Float, val stuckBots: Int, val oscillations: Int, val botSeconds: Int, val notes: List<String>)

    /** Plays a bot-only match, checking invariants every tick and measuring whether any bot "wants to move but cannot". */
    private fun match(seed: Long, skill: BotSkill, maxSeconds: Float = 700f): Stats {
        val w = BrWorld(seed, autoStartS = 0f, botSkill = skill)
        var t = 0f; var firstKill = -1f; var lastAlive = BrConst.FIELD
        val lastPos = HashMap<Int, Pair<Float, Float>>(); val still = HashMap<Int, Float>()
        val flips = HashMap<Int, Int>(); val prevDir = HashMap<Int, Pair<Float, Float>>(); var oscillations = 0; var stuck = 0; var botSeconds = 0; val notes = ArrayList<String>()
        while (w.phase != Phase.ENDED && t < maxSeconds) {
            w.update(DT); t += DT
            if (w.phase != Phase.LIVE) continue
            if (firstKill < 0f && w.aliveCount() < lastAlive) firstKill = w.matchTime
            lastAlive = w.aliveCount()
            val sample = (w.matchTime * 30).toInt() % 30 == 0 // once per second
            for (f in w.fighters.values) if (f.alive) {
                assertTrue(f.x.isFinite() && f.y.isFinite() && f.hp.isFinite(), "seed $seed: NaN fighter ${f.id}")
                assertTrue(w.map.isFree(f.x, f.y, BrConst.BODY_R - 1.5f), "seed $seed t=$t: ${f.name} is inside a wall at ${f.x},${f.y}")
                assertTrue(f.shield in 0f..BrWorld.MAX_SHIELD + 0.01f && f.hp <= f.maxHp + 0.01f, "seed $seed: bad hp/shield ${f.hp}/${f.shield}")
                assertTrue(f.medkits in 0..BrWorld.CARRY && f.cells in 0..BrWorld.CARRY)
                assertTrue(f.rounds in 0..f.weapon.mag)
                // walking back and forth every tick (a goal flip-flop) shows up as the movement vector repeatedly reversing
                val len = kotlin.math.hypot(f.input.dx, f.input.dy)
                if (len > 0.3f) {
                    val d = f.input.dx / len to f.input.dy / len
                    val pd = prevDir[f.id]
                    if (pd != null && d.first * pd.first + d.second * pd.second < -0.7f) flips[f.id] = (flips[f.id] ?: 0) + 1
                    prevDir[f.id] = d
                }
                if (sample) {
                    botSeconds++
                    if ((flips[f.id] ?: 0) >= 12) oscillations++ // 12+ reversals in one second
                    flips[f.id] = 0
                    val p = lastPos[f.id]
                    val wantsToMove = abs(f.input.dx) + abs(f.input.dy) > 0.3f && f.healKind == 0
                    if (p != null && Geo.dist(p.first, p.second, f.x, f.y) < 5f && wantsToMove) still[f.id] = (still[f.id] ?: 0f) + 1f else still[f.id] = 0f
                    lastPos[f.id] = f.x to f.y
                    if ((still[f.id] ?: 0f) >= 15f) { stuck++; still[f.id] = 0f; notes += "seed $seed $skill t=${w.matchTime.toInt()} ${f.name} at (${f.x.toInt()},${f.y.toInt()}) in=(${f.input.dx},${f.input.dy}) ${w.brainDebug(f.id)}" }
                }
            }
            assertTrue(w.zombies.size <= BrWorld.ZOMBIE_CAP)
        }
        return Stats(w, firstKill, stuck, oscillations, botSeconds, notes)
    }

    private fun abs(v: Float) = kotlin.math.abs(v)

    @Test fun botMatchesAlwaysFinishWithAWinner() {
        for (seed in 1L..8L) {
            val w = match(seed, BotSkill.NORMAL).world
            assertEquals(Phase.ENDED, w.phase, "seed $seed did not finish")
            assertTrue(w.matchTime < 650f, "seed $seed took ${w.matchTime}s")
            assertTrue(w.aliveCount() <= 1)
            val placements = w.fighters.values.filter { !it.alive || it.id == w.winnerId }.map { it.placement }.sorted()
            if (w.winnerId >= 0) assertEquals((1..BrConst.FIELD).toList(), placements, "seed $seed: placements must be a clean 1..12")
        }
    }

    @Test fun botsNeverGetStuckOrFlipFlop() {
        var stuck = 0; var osc = 0; var seconds = 0; val notes = ArrayList<String>()
        for (seed in 1L..10L) for (skill in BotSkill.values()) { val s = match(seed, skill); stuck += s.stuckBots; osc += s.oscillations; seconds += s.botSeconds; notes += s.notes }
        assertEquals(0, stuck, "bots that wanted to move but did not for 15 s: $notes")
        // Holding range in a fight legitimately makes a bot step back and forth now and then; a goal flip-flop shows up as
        // hundreds of seconds. Before the steering/hysteresis fixes this was about 4% of bot-seconds, now ~0.1%.
        println("BR jitter: $osc of $seconds bot-seconds")
        assertTrue(osc <= seconds * 0.005, "$osc of $seconds bot-seconds spent reversing direction 12+ times a second")
    }

    @Test fun pacingStaysInAHealthyBand() {
        // Regression guard for the tuning: early fights were once over in under a minute with the zone irrelevant.
        val runs = (1L..12L).map { match(it, BotSkill.NORMAL) }
        val avg = runs.map { it.world.matchTime }.average()
        println("BR pacing: avg ${"%.0f".format(avg)}s, shortest ${runs.minOf { it.world.matchTime }.toInt()}s, avg first kill ${"%.0f".format(runs.map { it.firstKill }.average())}s")
        assertTrue(avg in 150.0..330.0, "average match length $avg s")
        assertTrue(runs.all { it.world.matchTime > 90f }, "a match was over in under 90 s")
        assertTrue(runs.map { it.firstKill }.average() > 20.0, "first blood is too early: opening should be a loot phase")
    }

    @Test fun skillLevelsAreOrdered() {
        fun avgKillTime(s: BotSkill) = (1L..8L).map { match(it, s).firstKill }.average()
        val easy = avgKillTime(BotSkill.EASY); val hard = avgKillTime(BotSkill.HARD)
        assertTrue(easy > hard, "harder bots should find the first fight sooner (easy $easy, hard $hard)")
    }
}
