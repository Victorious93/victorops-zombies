package com.victorious.zombie.br

import com.victorious.zombie.logic.Characters
import com.victorious.zombie.net.ClientSession
import com.victorious.zombie.net.HostSession
import com.victorious.zombie.net.LoopbackLink
import com.victorious.zombie.sim.PlayerInput
import kotlin.math.hypot
import kotlin.test.*

/** Ids 0, 1, 2 are one squad (squad 0), id 3 is a lone enemy squad. All placed in the open, protection off. */
private fun squadWorld(): BrWorld {
    val w = liveWorld("snoop", "martha", "snoop", "martha", squadSize = 3)
    assertEquals(listOf(0, 0, 0, 1), listOf(0, 1, 2, 3).map { w.fighters.getValue(it).squad })
    return w
}

private fun BrWorld.f(id: Int) = fighters.getValue(id)

/** Knocks [id] to zero health from enemy 3 and checks they went down rather than out. */
private fun BrWorld.down(id: Int, by: Int = 3) {
    val t = f(id); t.shield = 0f; t.hp = 1f
    damage(t, 10f, by, "test")
    assertTrue(t.alive && t.downed, "${t.name} should be downed")
}

class BrSquadRulesTest {
    @Test fun squadsAreFilledHumansFirstThenBots() {
        for (size in 2..4) {
            val w = BrWorld(3, autoStartS = 0f, squadSize = size)
            w.join(0, "snoop"); w.join(1, "martha"); w.join(2, "snoop"); w.join(3, "martha"); w.startMatch()
            val bySquad = w.fighters.values.groupBy { it.squad }
            assertEquals(BrConst.FIELD / size, bySquad.size, "size $size")
            assertTrue(bySquad.values.all { it.size == size })
            assertEquals(w.humans().take(size).map { 0 }, w.humans().take(size).map { it.squad })
            if (size < 4) assertEquals(1, w.f(size).squad, "extra humans spill into squad 1")
        }
        val ffa = BrWorld(3, autoStartS = 0f); ffa.join(0, "snoop"); ffa.startMatch()
        assertEquals(BrConst.FIELD, ffa.fighters.values.map { it.squad }.toSet().size, "free-for-all: every fighter is their own squad")
    }

    @Test fun squadsLandTogetherAndApart() {
        for (seed in 1L..6L) {
            val w = BrWorld(seed, autoStartS = 0f, squadSize = 3); w.join(0, "snoop"); w.startMatch()
            val groups = w.fighters.values.groupBy { it.squad }
            for ((sq, m) in groups) for (a in m) for (b in m) assertTrue(hypot(a.x - b.x, a.y - b.y) < 170f, "seed $seed squad $sq lands spread out")
            val centres = groups.values.map { m -> m.map { it.x }.average() to m.map { it.y }.average() }
            for (i in centres.indices) for (j in i + 1 until centres.size)
                assertTrue(hypot(centres[i].first - centres[j].first, centres[i].second - centres[j].second) > 400.0, "seed $seed: squads $i and $j land on top of each other")
        }
    }

    @Test fun noFriendlyFireFromBulletsSplashAbilitiesOrDirectDamage() {
        val w = squadWorld(); val (x, y) = w.openSpot()
        // a gun fired through a teammate hits the enemy behind (the lancer even keeps its pierce)
        w.place(0, x, y); w.place(1, x + 120, y); w.place(3, x + 240, y); w.place(2, x, y + 300)
        w.f(0).weapon = BrWeapon(BrGuns.LANCER, Rarity.COMMON); w.f(0).rounds = 4
        w.applyInput(0, PlayerInput(aimX = 1f, fire = true)); w.run(0.5f); w.applyInput(0, PlayerInput())
        assertEquals(w.f(1).maxHp, w.f(1).hp, "bullet passed through the teammate"); assertTrue(w.f(3).hp < w.f(3).maxHp, "and hit the enemy")
        // explosion splash
        w.f(3).hp = w.f(3).maxHp; w.f(3).shield = 0f
        w.place(0, x, y); w.place(3, x + 200, y); w.place(1, x + 200, y + 40)
        w.f(0).weapon = BrWeapon(BrGuns.NOVA, Rarity.COMMON); w.f(0).rounds = 3; w.f(0).fireCd = 0f
        w.applyInput(0, PlayerInput(aimX = 1f, fire = true)); w.run(0.7f); w.applyInput(0, PlayerInput())
        assertTrue(w.f(3).hp < w.f(3).maxHp, "the enemy takes the nova"); assertEquals(w.f(1).maxHp, w.f(1).hp, "splash spares the teammate")
        // Bass Drop: no damage, no knockback for the teammate, but the enemy is hit
        w.f(3).hp = w.f(3).maxHp
        w.place(0, x, y); w.place(1, x + 90, y); w.place(3, x - 90, y)
        w.applyInput(0, PlayerInput(ability = true)); w.run(0.4f); w.applyInput(0, PlayerInput())
        assertEquals(w.f(1).maxHp, w.f(1).hp); assertEquals(x + 90, w.f(1).x, 0.01f, "teammate is not knocked back")
        assertTrue(w.f(3).hp < w.f(3).maxHp, "the enemy is")
        assertFalse(w.damage(w.f(1), 500f, 0, "direct"), "even a direct call cannot hurt a mate"); assertEquals(w.f(1).maxHp, w.f(1).hp)
    }

    @Test fun teammatesNeverBlockOrPushEachOther() {
        val w = squadWorld(); val (x, y) = w.openSpot()
        w.place(0, x, y); w.place(1, x + 2, y); w.place(3, x + 700, y + 700); w.place(2, x, y + 300)
        w.run(0.5f)
        assertTrue(hypot(w.f(0).x - w.f(1).x, w.f(0).y - w.f(1).y) < 3f, "mates stay on top of each other")
        w.place(3, x + 2, y + 2)
        w.run(0.5f)
        assertTrue(hypot(w.f(0).x - w.f(3).x, w.f(0).y - w.f(3).y) > BrConst.BODY_R * 1.8f, "an enemy is pushed apart")
    }

    @Test fun zeroHealthMeansDownedWhileAMateCanMoveAndEliminatedOtherwise() {
        val w = squadWorld()
        val alive = w.aliveCount()
        w.down(1)
        assertEquals(alive, w.aliveCount(), "downed fighters are still in the match"); assertEquals(0, w.f(3).kills, "going down is not a kill")
        assertEquals(0f, w.f(1).hp); assertEquals(BrWorld.BLEED_TIME, w.f(1).downedT, 0.01f)
        assertTrue(w.snapshot(0).feed.any { it.contains("downed") })
        // the lone enemy has nobody to revive them: straight out
        val e = w.f(3); e.hp = 1f; e.shield = 0f
        assertTrue(w.damage(e, 10f, 0, "test")); assertFalse(e.alive); assertEquals(1, w.f(0).kills)
    }

    @Test fun downedFightersCrawlAndCannotActOrBeHealedByThemselves() {
        val w = squadWorld(); val (x, y) = w.openSpot()
        w.place(0, x, y); w.place(2, x, y + 300); w.place(3, x + 800, y + 800)
        w.place(1, x + 200, y); w.down(1)
        val f = w.f(1); f.medkits = 2; f.rounds = f.weapon.mag
        w.applyInput(1, PlayerInput(dx = 1f, aimX = 1f, fire = true, heal = true, reload = true, ability = true))
        w.run(1f)
        val moved = f.x - (x + 200)
        assertTrue(moved > 0.15f * BrWorld.SPEED * f.character.speedMult && moved < 0.35f * BrWorld.SPEED * f.character.speedMult, "crawls at about a quarter speed, moved $moved")
        assertEquals(f.weapon.mag, f.rounds, "cannot fire"); assertEquals(0, f.healKind, "cannot heal"); assertTrue(w.bullets.isEmpty()); assertEquals(0f, f.abilityCd.coerceAtLeast(0f))
    }

    @Test fun bleedingOutEliminatesAfterThirtySecondsAndDropsLoot() {
        val w = squadWorld(); w.down(1)
        w.place(3, 100f, 100f)
        w.run(BrWorld.BLEED_TIME - 1.5f); assertTrue(w.f(1).alive, "still bleeding")
        w.run(2f)
        assertFalse(w.f(1).alive); assertEquals(1, w.statBleedOuts)
        assertTrue(w.loot.any { it.kind == LootKind.CELL }, "drops a shield cell")
        assertTrue(w.snapshot(0).feed.any { it.contains("eliminated") || it.contains("bled out") })
        assertEquals(1, w.f(3).kills, "the fighter who downed them gets the credit")
    }

    @Test fun enemyHitsAndZoneAndHordeSpeedUpTheBleedOut() {
        val w = squadWorld(); w.down(1)
        val t = w.f(1); assertEquals(30f, t.downedT, 0.01f)
        w.damage(t, 40f, 3, "gun"); assertEquals(30f - 40f * BrWorld.BLEED_PER_DMG, t.downedT, 0.01f); assertEquals(0f, t.hp)
        val before = t.downedT; w.damage(t, 8f, -1, "the Dead Zone", interrupt = false); assertEquals(before - 8f * BrWorld.BLEED_PER_DMG, t.downedT, 0.01f)
        assertTrue(w.damage(t, 500f, 3, "gun")); assertFalse(t.alive); assertEquals(1, w.f(3).kills)
    }

    @Test fun zoneDamageReachesDownedFighters() {
        val w = squadWorld()
        repeat(30 * 90) { w.fighters.values.forEach { it.protectedT = 99f }; w.update(DT) }
        assertTrue(w.zoneIdx >= 1)
        var spot: Pair<Float, Float>? = null
        for (k in 0 until 72) { val a = k * 2 * Math.PI.toFloat() / 72; val px = w.zoneCx + kotlin.math.cos(a) * (w.zoneR + 120f); val py = w.zoneCy + kotlin.math.sin(a) * (w.zoneR + 120f); if (w.map.isFree(px, py, 20f) && !w.inZone(px, py)) { spot = px to py; break } }
        assertNotNull(spot)
        w.fighters.values.forEach { it.protectedT = 0f }
        w.place(0, w.zoneCx, w.zoneCy); w.place(2, w.zoneCx + 5, w.zoneCy); w.place(3, w.zoneCx - 5, w.zoneCy)
        w.f(3).protectedT = 1e9f
        w.f(1).x = spot.first; w.f(1).y = spot.second; w.down(1, by = -1)
        w.f(1).protectedT = 0f
        val t0 = w.f(1).downedT; w.run(2f)
        assertTrue(w.f(1).downedT < t0 - 2f - 0.4f, "bleed ${t0 - w.f(1).downedT}s in 2 s: the zone must speed it up")
    }

    @Test fun holdingUseNextToADownedMateRevivesThem() {
        val w = squadWorld(); val (x, y) = w.openSpot()
        w.place(0, x, y); w.place(1, x + 40, y); w.place(2, x, y + 400); w.place(3, x + 900, y + 900)
        w.down(1); w.f(1).medkits = 0
        val t0 = w.f(1).downedT
        w.applyInput(0, PlayerInput(use = true))
        w.run(BrWorld.REVIVE_TIME - 0.6f)
        assertTrue(w.f(1).downed && w.f(1).reviveP in 0.7f..0.95f, "mid-revive, progress ${w.f(1).reviveP}")
        assertEquals(t0, w.f(1).downedT, 0.05f, "the bleed-out clock pauses while somebody works on you")
        assertEquals(1, w.statRevivesStarted)
        val snap = w.snapshot(0); assertTrue(snap.self!!.reviveProgress > 0.6f); assertTrue(snap.fighters.first { it.id == 0 }.reviving)
        w.run(1f)
        val r = w.f(1)
        assertFalse(r.downed); assertEquals(r.maxHp * BrWorld.REVIVE_HP, r.hp, 0.5f); assertEquals(0f, r.shield)
        assertEquals(1, w.f(0).revives); assertEquals(1, w.statRevives); assertTrue(w.snapshot(0).feed.any { it.contains("revived") })
    }

    @Test fun theReviverMovesSlowlyAndDoesNotSwapWeaponsWhileAMateNeedsThem() {
        val w = squadWorld(); val (x, y) = w.openSpot()
        w.place(0, x, y); w.place(1, x + 30, y); w.place(2, x, y + 400); w.place(3, x + 900, y + 900)
        w.down(1)
        val gun = w.f(0).weapon
        w.loot += Loot(901, LootKind.WEAPON, x + 5, y, BrWeapon(BrGuns.RIFLE, Rarity.EPIC))
        assertTrue(w.snapshot(0).self!!.prompt.startsWith("REVIVE"), "prompt: ${w.snapshot(0).self!!.prompt}")
        w.applyInput(0, PlayerInput(use = true, dy = 1f)); w.run(0.3f)
        assertEquals(gun, w.f(0).weapon, "USE revives instead of swapping")
        val moved = w.f(0).y - y // 0.3 s is short enough to stay within reach of the mate the whole time
        val full = BrWorld.SPEED * w.f(0).character.speedMult * 0.3f
        assertTrue(moved > 0.4f * full && moved < 0.6f * full, "reviver moves at about half speed, moved $moved of $full")
    }

    @Test fun damageToTheReviverInterruptsAndProgressDecays() {
        val w = squadWorld(); val (x, y) = w.openSpot()
        w.place(0, x, y); w.place(1, x + 40, y); w.place(2, x, y + 400); w.place(3, x + 900, y + 900)
        w.down(1)
        w.applyInput(0, PlayerInput(use = true)); w.run(2f)
        val p = w.f(1).reviveP; assertTrue(p in 0.4f..0.6f, "p=$p")
        w.damage(w.f(0), 5f, 3, "gun")
        w.run(0.5f)
        assertTrue(w.f(1).reviveP < p, "no progress (and a little decay) right after the reviver is hit: ${w.f(1).reviveP} vs $p")
        assertEquals(-1, w.f(0).reviveTarget); assertTrue(w.statRevivesInterrupted >= 1)
        w.run(1f) // still holding USE: the channel resumes once the flinch is over
        assertTrue(w.f(1).reviveP > p - 0.2f && w.f(0).reviveTarget == w.f(1).id, "resumes: ${w.f(1).reviveP}")
        // letting go makes the progress fall back
        val q = w.f(1).reviveP
        w.applyInput(0, PlayerInput()); w.run(2f)
        assertTrue(w.f(1).reviveP < q - 0.1f && w.f(1).downed, "released: ${w.f(1).reviveP} vs $q")
        // zone damage (interrupt = false) does not break a channel
        w.applyInput(0, PlayerInput(use = true)); w.run(0.3f)
        w.damage(w.f(0), 3f, -1, "the Dead Zone", interrupt = false); w.run(0.1f)
        assertEquals(w.f(1).id, w.f(0).reviveTarget)
    }

    @Test fun reviveNeedsTheReviverWithinRange() {
        val w = squadWorld(); val (x, y) = w.openSpot()
        w.place(0, x, y); w.place(1, x + BrWorld.REVIVE_RANGE + 40f, y); w.place(2, x, y + 400); w.place(3, x + 900, y + 900)
        w.down(1)
        w.applyInput(0, PlayerInput(use = true)); w.run(5f)
        assertTrue(w.f(1).downed && w.f(1).reviveP == 0f && w.statRevivesStarted == 0, "out of reach")
        w.place(0, x + 40f + 20f, y)
        w.run(BrWorld.REVIVE_TIME + 0.5f)
        assertFalse(w.f(1).downed, "in reach it works")
        // enemies cannot revive
        val w2 = squadWorld(); w2.place(0, x, y); w2.place(1, x + 30, y); w2.place(2, x, y + 400); w2.place(3, x + 60, y)
        w2.down(1); w2.applyInput(3, PlayerInput(use = true)); w2.run(5f)
        assertTrue(w2.f(1).downed, "an enemy standing next to you does not revive you")
    }

    @Test fun lastTeammateAbleToMoveGoingDownEliminatesTheWholeSquadWithOnePlacement() {
        val w = squadWorld()
        w.down(1); w.down(2)
        assertTrue(w.f(0).alive)
        w.f(0).hp = 1f; w.f(0).shield = 0f
        assertTrue(w.damage(w.f(0), 10f, 3, "test"), "nobody left who can revive: eliminated")
        listOf(0, 1, 2).forEach { assertFalse(w.f(it).alive, "squad member $it must be out"); assertEquals(2, w.f(it).placement, "wiped with two squads left: placed 2nd") }
        assertEquals(3, w.f(3).kills, "the downer is credited for all three")
        w.update(DT)
        assertEquals(Phase.ENDED, w.phase); assertEquals(1, w.winnerSquad); assertEquals(3, w.winnerId); assertEquals(1, w.f(3).placement)
    }

    @Test fun squadPlacementIsTheNumberOfSquadsStillInTheMatch() {
        val w = squadWorld()
        w.f(2).squad = 2 // three squads: {0,1}, {2}, {3}
        w.f(3).hp = 1f; w.f(3).shield = 0f; w.damage(w.f(3), 5f, 0, "x")
        assertEquals(3, w.f(3).placement); assertEquals(Phase.LIVE, w.phase)
        w.f(2).hp = 1f; w.f(2).shield = 0f; w.damage(w.f(2), 5f, 1, "x")
        assertEquals(2, w.f(2).placement)
        w.update(DT)
        assertEquals(Phase.ENDED, w.phase); assertEquals(0, w.winnerSquad)
        assertEquals(listOf(1, 1), listOf(0, 1).map { w.f(it).placement }); assertEquals(1, w.f(0).kills); assertEquals(1, w.f(1).kills, "kills stay individual")
        assertEquals("Snoop's squad is the last one standing!", w.snapshot(0).banner)
    }

    @Test fun matchEndsWhenNoHumanIsLeftEvenIfBotSquadsRemain() {
        val w = BrWorld(4, autoStartS = 0f, squadSize = 3)
        w.join(0, "snoop"); w.startMatch()
        repeat(30 * 7) { w.update(DT) }
        assertEquals(Phase.LIVE, w.phase)
        w.fighters.values.forEach { it.protectedT = 0f }
        val me = w.f(0); val enemy = w.fighters.values.first { it.squad != me.squad }
        val mates = w.fighters.values.filter { it.squad == me.squad && it !== me }
        assertEquals(2, mates.size)
        w.damage(me, 9999f, enemy.id, "test")
        assertTrue(me.downed, "the human goes down first: their bots can still revive them")
        w.update(DT); assertEquals(Phase.LIVE, w.phase)
        mates.forEach { w.damage(it, 9999f, enemy.id, "test") }
        assertFalse(me.alive, "no mate can move any more: the human is out")
        w.update(DT)
        assertEquals(Phase.ENDED, w.phase); assertTrue(w.squadsAlive() > 1, "bot squads were still alive"); assertEquals(-1, w.winnerId)
    }

    @Test fun eliminatedHumansSpectateAMateFirst() {
        val w = squadWorld(); w.down(0)
        w.damage(w.f(0), 500f, 3, "x"); assertFalse(w.f(0).alive)
        val s = w.snapshot(0)
        assertTrue(s.focusId == 1 || s.focusId == 2, "spectating a mate, got ${s.focusId}"); assertFalse(s.self!!.alive)
        assertTrue(s.fighters.any { it.id == s.focusId })
    }

    @Test fun freeForAllStillEliminatesAtOnce() {
        val w = liveWorld("snoop", "martha")
        w.f(1).hp = 1f; w.f(1).shield = 0f
        assertTrue(w.damage(w.f(1), 5f, 0, "x")); assertFalse(w.f(1).alive); assertFalse(w.f(1).downed); assertEquals(0, w.statDowns)
        val s = w.snapshot(0); assertEquals(1, s.squadSize)
    }
}

class BrSquadNetTest {
    @Test fun snapshotsCarrySquadDownedAndReviveStateAndAlwaysIncludeMates() {
        val w = squadWorld(); val (x, y) = w.openSpot()
        w.place(0, x, y); w.place(1, x + 40, y); w.place(2, x, y + 1000f); w.place(3, x + 500, y + 300)
        w.down(1); w.applyInput(0, PlayerInput(use = true)); w.run(1.5f)
        val s = w.snapshot(0)
        assertTrue(hypot(w.f(2).x - x, w.f(2).y - y) > BrConst.VIEW_RANGE)
        assertTrue(s.fighters.any { it.id == 2 }, "a mate beyond view range is still sent")
        val d = BrCodec.fromText(BrCodec.toText(s))
        val m = d.fighters.first { it.id == 1 }
        assertTrue(m.downed && m.alive); assertEquals(0, m.squad); assertEquals(1f - 1.5f / BrWorld.BLEED_TIME, m.bleed, 0.1f + 1.5f / BrWorld.BLEED_TIME); assertEquals(w.f(1).reviveP, m.reviveP, 0.01f)
        assertTrue(d.fighters.first { it.id == 0 }.reviving); assertFalse(d.fighters.first { it.id == 3 }.downed); assertEquals(1, d.fighters.first { it.id == 3 }.squad)
        assertEquals(3, d.squadSize); assertEquals(2, d.squadsAlive)
        assertEquals(0, d.self!!.squad); assertEquals(w.f(1).reviveP, d.self!!.reviveProgress, 0.01f); assertFalse(d.self!!.downed)
        val dn = BrCodec.decode(BrCodec.encode(w.snapshot(1))).self!!
        assertTrue(dn.downed); assertEquals(w.f(1).reviveP, dn.reviveProgress, 0.01f); assertEquals("", dn.prompt)
    }

    @Test fun squadMatchSnapshotsStaySmall() {
        val w = BrWorld(3, autoStartS = 0f, squadSize = 3)
        w.join(0, "snoop"); w.run(2f)
        var biggest = 0
        repeat(30 * 120) { w.update(DT); if (it % 15 == 0) biggest = maxOf(biggest, BrCodec.encode(w.snapshot(0)).size) }
        println("BR biggest squad snapshot: $biggest bytes")
        assertTrue(biggest < 6000, "snapshot of $biggest bytes is too big")
    }

    @Test fun garbageInTheSquadFieldsIsRejectedNotCrashing() {
        val good = BrCodec.encode(squadWorld().snapshot(0))
        val rnd = kotlin.random.Random(8)
        repeat(400) { val b = good.copyOf(); repeat(4) { b[rnd.nextInt(b.size)] = rnd.nextInt().toByte() }; runCatching { BrCodec.decode(b) } }
        assertFails { BrCodec.decode(good.copyOf(good.size - 3)) }
    }

    @Test fun aClientJoinsTheLobbyOfASquadMatchAndLearnsTheMode() {
        val host = HostSession.createRoyale(Characters.SNOOP, autoStartS = 60f, squadSize = 3)
        val (a, b) = LoopbackLink.pair(); host.attach(a)
        val client = ClientSession(b, "martha")
        host.tick(0.05f); repeat(10) { host.tick(0.07f) }
        val lobby = client.latestRoyale!!
        assertEquals(Phase.LOBBY.ordinal, lobby.phase); assertEquals(3, lobby.squadSize); assertEquals(listOf("Snoop", "Martha"), lobby.lobby)
        host.sim.applyInput(0, PlayerInput(use = true)); host.tick(0.05f)
        repeat(160) { client.tick(0.05f, PlayerInput(dx = 1f)); host.tick(0.05f) }
        val live = client.latestRoyale!!
        assertEquals(Phase.LIVE.ordinal, live.phase); assertEquals(3, live.squadSize); assertEquals(BrConst.FIELD / 3, live.squads)
        val me = live.fighters.first { it.id == live.meId }
        assertEquals(3, live.fighters.count { it.squad == me.squad }, "the whole squad is visible to the client")
        // the host picks the mode in the lobby, before it starts
        val w = BrWorld(1, autoStartS = 60f, withBots = false); w.join(0, "snoop"); w.setSquadSize(4)
        assertEquals(4, BrCodec.decode(BrCodec.encode(w.snapshot(0))).squadSize)
        w.setSquadSize(9); assertEquals(BrWorld.MAX_SQUAD, w.squadSize)
    }
}
