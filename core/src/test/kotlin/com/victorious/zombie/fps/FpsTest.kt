package com.victorious.zombie.fps

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.test.*

private const val DT = 1 / 30f

private fun FpsWorld.run(seconds: Float, input: () -> FpsInput = { FpsInput(yaw = player.yaw) }) { repeat((seconds / DT).toInt()) { update(DT, input()) } }
private fun FpsWorld.prop(kind: PropKind, perk: Perk? = null, gun: FpsGun? = null) = map.props.first { it.kind == kind && (perk == null || it.perk == perk) && (gun == null || it.gun == gun) }

/** Stands the player right in front of a prop, facing it. */
private fun FpsWorld.standAt(p: Prop) {
    player.x = map.centre(p.tx) + p.fx * (FpsMap.CELL / 2 + 0.6f); player.y = map.centre(p.ty) + p.fy * (FpsMap.CELL / 2 + 0.6f)
    player.yaw = atan2(-p.fy.toFloat(), -p.fx.toFloat())
}
private fun FpsWorld.press(use: Boolean = false, knife: Boolean = false, swap: Boolean = false) {
    update(DT, FpsInput(yaw = player.yaw, use = use, knife = knife, swap = swap)); update(DT, FpsInput(yaw = player.yaw))
}
/** A quiet world: the first round never starts, so tests control every zombie. */
private fun quiet(seed: Long = 1): FpsWorld = FpsWorld(seed, autoRounds = false).also { it.update(DT, FpsInput(yaw = it.player.yaw)) }
private fun FpsWorld.zombieAt(x: Float, y: Float, hp: Float = 150f): FpsZombie {
    val z = FpsZombie(9000 + zombies.size, x, y, hp, 1.3f, 0, 1f, 0); z.state = ZState.INSIDE; zombies += z; return z
}

class FpsMapTest {
    @Test fun stationParsesIntoASoundMap() {
        val m = FpsMap()
        assertEquals(4, m.zoneCount); assertTrue(m.zonesConnected())
        assertEquals(10, m.windows.size); assertEquals(3, m.doors.size)
        assertEquals(4, m.props.count { it.kind == PropKind.WALL_BUY }); assertEquals(4, m.props.count { it.kind == PropKind.PERK })
        assertEquals(1, m.props.count { it.kind == PropKind.BOX }); assertEquals(1, m.props.count { it.kind == PropKind.POWER }); assertEquals(1, m.props.count { it.kind == PropKind.FORGE })
        assertTrue(m.walkable(m.tileOf(m.startX), m.tileOf(m.startY))); assertEquals(0, m.zoneAt(m.tileOf(m.startX), m.tileOf(m.startY)))
        assertTrue(m.windows.count { it.zone == 0 } >= 2, "the start room needs windows")
        for (w in m.windows) {
            assertTrue(m.walkable(w.inX, w.inY), "window ${w.id} must open onto floor"); assertTrue(m.outsideWalk(w.outX, w.outY))
            assertTrue(m.outsideFlow[w.id].count { it in 2..4 } > 0, "window ${w.id} has nowhere for zombies to spawn")
        }
        for (p in m.props) assertTrue(m.walkable(p.tx + p.fx, p.ty + p.fy), "${p.kind} at ${p.tx},${p.ty} must face floor")
        // the power and Ironhide sit behind two doors, the forge is in the start room
        assertEquals(3, m.props.first { it.kind == PropKind.POWER }.zone); assertEquals(0, m.props.first { it.kind == PropKind.FORGE }.zone)
    }

    @Test fun everyFloorTileIsReachableOnceTheDoorsAreOpen() {
        val m = FpsMap(); m.doors.forEach { it.open = true }
        m.flowTo(m.tileOf(m.startX), m.tileOf(m.startY))
        for (y in 0 until m.h) for (x in 0 until m.w) if (m.walkable(x, y)) assertTrue(m.flow[y * m.w + x] >= 0, "floor $x,$y unreachable")
        val closed = FpsMap(); closed.flowTo(closed.tileOf(closed.startX), closed.tileOf(closed.startY))
        for (y in 0 until closed.h) for (x in 0 until closed.w) if (closed.flow[y * closed.w + x] >= 0) assertEquals(0, closed.zoneAt(x, y), "closed doors keep zone 0 sealed")
    }

    @Test fun castAndResolveRespectWalls() {
        val m = FpsMap()
        val d = m.cast(m.startX, m.startY, 0f, -1f, 100f) { x, y -> m.stopsBullets(x, y) } // north: the wall (door) between zone 0 and 1
        assertTrue(d in 3f..12f, "hit the north wall at $d")
        val out = FloatArray(2)
        m.resolve(m.startX, 0.5f, 0.35f, out) { x, y -> !m.walkable(x, y) }
        assertTrue(m.walkable(m.tileOf(out[0]), m.tileOf(out[1])) || out[1] != 0.5f)
    }
}

class FpsRulesTest {
    @Test fun roundsRampLikeTheClassics() {
        assertEquals(150f, FpsRules.zombieHealth(1)); assertEquals(950f, FpsRules.zombieHealth(9)); assertEquals(1045f, FpsRules.zombieHealth(10), 0.5f)
        assertEquals(listOf(6, 8, 13, 18, 24), (1..5).map { FpsRules.zombieCount(it) })
        assertTrue((1..30).zipWithNext().all { (a, b) -> FpsRules.zombieCount(b) >= FpsRules.zombieCount(a) && FpsRules.zombieHealth(b) > FpsRules.zombieHealth(a) })
        assertTrue(FpsRules.spawnInterval(1) > FpsRules.spawnInterval(10)); assertEquals(0f, FpsRules.runShare(3))
        // the start pistol kills a round-1 zombie in one headshot or three body shots
        assertTrue(FpsGuns.PISTOL.damage * FpsGuns.PISTOL.headMult >= FpsRules.zombieHealth(1)); assertTrue(FpsGuns.PISTOL.damage * 3 >= FpsRules.zombieHealth(1))
    }
}

class FpsCombatTest {
    @Test fun headshotsKillForMorePointsThanBodyShots() {
        val w = quiet(); val p = w.player
        val z = w.zombieAt(p.x, p.y - 5f)
        p.yaw = atan2(z.y - p.y, z.x - p.x)
        val headPitch = atan2(1.62f * z.scale - FpsWorld.EYE, 5f)
        val pts = p.points
        w.update(DT, FpsInput(yaw = p.yaw, pitch = headPitch, fire = true))
        assertFalse(z.alive, "one pistol headshot kills on round 1"); assertTrue(z.headless)
        assertEquals(pts + FpsRules.HEADSHOT_KILL_POINTS, p.points); assertEquals(1, p.headshots); assertEquals(7, p.gun.mag)
        // body shot: 60 damage and 10 points
        val z2 = w.zombieAt(p.x, p.y - 5f); w.run(0.3f)
        val bodyPitch = atan2(0.8f - FpsWorld.EYE, 5f)
        val pts2 = p.points
        w.update(DT, FpsInput(yaw = p.yaw, pitch = bodyPitch, fire = true))
        assertEquals(150f - 60f, z2.hp, 0.01f); assertEquals(pts2 + FpsRules.HIT_POINTS, p.points)
    }

    @Test fun wallsStopBullets() {
        val w = quiet(); val p = w.player
        val z = w.zombieAt(p.x, 2f * FpsMap.CELL + 1f) // in zone 1, on the far side of the wall north of the start room
        p.x = 9f * FpsMap.CELL + 1f // in front of a solid wall tile, not the door
        p.yaw = atan2(z.y - p.y, z.x - p.x)
        repeat(5) { w.update(DT * 6, FpsInput(yaw = p.yaw, pitch = atan2(0.8f - FpsWorld.EYE, hypot(z.x - p.x, z.y - p.y)), fire = true)) }
        assertEquals(150f, z.hp)
    }

    @Test fun theKnifeKillsEarlyZombiesForTheMostPoints() {
        val w = quiet(); val p = w.player
        val z = w.zombieAt(p.x + 1.1f, p.y); p.yaw = 0f
        val pts = p.points
        w.press(knife = true)
        assertFalse(z.alive); assertEquals(pts + FpsRules.KNIFE_KILL_POINTS, p.points)
        val behind = w.zombieAt(p.x - 1.1f, p.y); w.run(1f); w.press(knife = true)
        assertTrue(behind.alive, "the knife only hits what you face")
    }

    @Test fun reloadMovesAmmoFromReserveAndQuickhandHalvesIt() {
        val w = quiet(); val g = w.player.gun; g.mag = 2
        w.update(DT, FpsInput(yaw = w.player.yaw, reload = true))
        assertTrue(w.player.reloadT > 1f)
        w.run(1.6f)
        assertEquals(8, g.mag); assertEquals(64 - 6, g.reserve)
        w.player.perks += Perk.QUICKHAND; g.mag = 0
        w.update(DT, FpsInput(yaw = w.player.yaw, reload = true)); assertEquals(FpsGuns.PISTOL.reload / 2, w.player.reloadT, 0.05f)
    }
}

class FpsEconomyTest {
    @Test fun wallBuysCostPointsAndSecondBuyIsAmmo() {
        val w = quiet(); val p = w.player
        val wall = w.prop(PropKind.WALL_BUY, gun = FpsGuns.RANGER)
        w.standAt(wall); w.update(DT, FpsInput(yaw = p.yaw))
        assertTrue(w.prompt.contains("Ranger M1") && w.prompt.contains("500"), w.prompt)
        p.points = 400; w.press(use = true)
        assertEquals(1, p.guns.size, "cannot afford it")
        p.points = 600; w.press(use = true)
        assertEquals(2, p.guns.size); assertEquals(FpsGuns.RANGER, p.gun.gun); assertEquals(100, p.points)
        p.gun.reserve = 0; p.points = 300; w.press(use = true)
        assertEquals(FpsGuns.RANGER.reserve, p.gun.reserve); assertEquals(50, p.points, "ammo costs half")
    }

    @Test fun doorsOpenZonesAndLetZombiesSpawnThere() {
        val w = quiet(); val p = w.player
        val d = w.map.doors.first { setOf(it.zoneA, it.zoneB) == setOf(0, 1) }
        p.x = w.map.centre(d.tx); p.y = w.map.centre(d.ty) + FpsMap.CELL // just south of the door, in zone 0
        p.points = 800; w.press(use = true)
        assertTrue(d.open); assertTrue(w.zoneOpen[1]); assertEquals(50, p.points)
        p.y = w.map.centre(d.ty); w.update(DT, FpsInput(yaw = p.yaw))
        assertTrue(w.map.walkable(d.tx, d.ty)); assertEquals(d.ty, w.map.tileOf(p.y), "can walk through the open door")
    }

    @Test fun perksNeedPowerExceptSecondWindAndForgeUpgrades() {
        val w = quiet(); val p = w.player; p.points = 20000
        w.standAt(w.prop(PropKind.PERK, perk = Perk.QUICKHAND)); w.update(DT, FpsInput(yaw = p.yaw))
        w.zoneOpen[1] = true; w.zoneOpen[3] = true; w.update(DT, FpsInput(yaw = p.yaw))
        assertTrue(w.prompt.contains("power"), w.prompt)
        w.press(use = true); assertFalse(Perk.QUICKHAND in p.perks)
        w.standAt(w.prop(PropKind.PERK, perk = Perk.SECOND_WIND)); w.press(use = true); assertTrue(Perk.SECOND_WIND in p.perks)
        w.standAt(w.prop(PropKind.POWER)); w.press(use = true); assertTrue(w.power)
        w.standAt(w.prop(PropKind.PERK, perk = Perk.IRONHIDE)); w.press(use = true)
        assertTrue(Perk.IRONHIDE in p.perks); assertEquals(FpsRules.IRONHIDE_HP, p.maxHp); assertEquals(FpsRules.IRONHIDE_HP, p.hp)
        val before = p.points
        w.standAt(w.prop(PropKind.FORGE)); w.press(use = true)
        assertTrue(p.gun.forged); assertEquals(before - FpsRules.FORGE_COST, p.points)
        assertEquals(120f, p.gun.damage); assertTrue(p.gun.magSize > FpsGuns.PISTOL.mag)
    }

    @Test fun mysteryBoxRollsAGunYouDoNotHave() {
        val w = quiet(); val p = w.player; p.points = 5000; w.zoneOpen[1] = true
        w.standAt(w.prop(PropKind.BOX)); w.press(use = true)
        assertEquals(BoxState.ROLLING, w.boxState); assertEquals(5000 - FpsRules.BOX_COST, p.points)
        w.run(FpsWorld.ROLL_TIME + 0.2f)
        assertEquals(BoxState.READY, w.boxState); val g = w.boxGun!!
        assertTrue(g.inBox && g != FpsGuns.PISTOL)
        w.press(use = true)
        assertEquals(g, p.gun.gun); assertEquals(BoxState.IDLE, w.boxState)
    }

    @Test fun rebuildingBoardsPaysUpToTheCap() {
        val w = quiet(); val p = w.player
        val win = w.map.windows.first { it.zone == 0 }; win.boards = 0
        p.x = w.map.centre(win.inX); p.y = w.map.centre(win.inY)
        val pts = p.points
        w.run(FpsWorld.REPAIR_TIME * 3 + 0.1f) { FpsInput(yaw = p.yaw, use = true) }
        assertEquals(3, win.boards); assertEquals(pts + 30, p.points)
    }

    @Test fun powerUpsDoWhatTheySay() {
        val w = quiet(); val p = w.player
        p.gun.reserve = 0; w.applyPowerUp(PowerUp.MAX_AMMO); assertEquals(64, p.gun.reserve)
        w.applyPowerUp(PowerUp.DOUBLE_POINTS)
        val z = w.zombieAt(p.x + 1.1f, p.y); p.yaw = 0f
        val pts = p.points; w.press(knife = true); assertEquals(pts + 2 * FpsRules.KNIFE_KILL_POINTS, p.points)
        w.applyPowerUp(PowerUp.INSTA_KILL)
        val tough = w.zombieAt(p.x + 1.1f, p.y, hp = 5000f); w.run(1f); w.press(knife = true); assertFalse(tough.alive, "insta-kill")
        w.map.windows.forEach { it.boards = 1 }; w.applyPowerUp(PowerUp.CARPENTER); assertTrue(w.map.windows.all { it.boards == Window.MAX_BOARDS })
        repeat(3) { w.zombieAt(p.x + 4f, p.y + it) }; w.applyPowerUp(PowerUp.NUKE); assertEquals(0, w.aliveZombies)
        assertFalse(z.alive)
    }

    @Test fun downedWithoutSecondWindIsGameOverAndWithItYouGetUp() {
        val w = quiet(); val p = w.player
        p.perks += Perk.SECOND_WIND
        w.hurtPlayer(200f, 0f, 0f)
        assertTrue(p.downed); assertFalse(w.over); assertFalse(Perk.SECOND_WIND in p.perks)
        w.run(FpsWorld.DOWN_TIME + 0.2f)
        assertFalse(p.downed); assertEquals(p.maxHp, p.hp); assertTrue(p.invulnT > 0f)
        w.run(3.5f); w.hurtPlayer(200f, 0f, 0f)
        assertTrue(w.over); assertTrue(w.events.any { it.type == FpsEvent.Type.GAME_OVER } || w.over)
    }

    @Test fun healthComesBackAfterAFewQuietSeconds() {
        val w = quiet(); val p = w.player
        w.hurtPlayer(50f, 0f, 0f); assertEquals(50f, p.hp)
        w.run(2f); assertEquals(50f, p.hp)
        w.run(3f); assertEquals(p.maxHp, p.hp)
    }
}

class FpsRoundTest {
    /** The player stands still and cannot die; zombies must find their way in and reach them. */
    @Test fun zombiesTearBoardsClimbInAndReachThePlayer() {
        for (seed in 1L..4L) {
            val w = FpsWorld(seed); val p = w.player
            var attacked = false; var torn = false; var stuck = 0
            val last = HashMap<Int, Pair<Float, Float>>(); val still = HashMap<Int, Float>()
            var t = 0f
            while (t < 120f && !attacked) {
                p.invulnT = 1e9f
                w.update(DT, FpsInput(yaw = p.yaw)); t += DT
                if (w.events.any { it.type == FpsEvent.Type.BOARD_TORN }) torn = true
                if (w.zombies.any { it.state == ZState.INSIDE && it.attacking }) attacked = true
                if ((t * 30).toInt() % 30 == 0) for (z in w.zombies) if (z.state == ZState.INSIDE && !z.attacking && hypot(z.x - p.x, z.y - p.y) > 1.6f) {
                    val l = last[z.id]
                    if (l != null && hypot(l.first - z.x, l.second - z.y) < 0.2f) still[z.id] = (still[z.id] ?: 0f) + 1f else still[z.id] = 0f
                    if ((still[z.id] ?: 0f) >= 8f) { stuck++; still[z.id] = 0f }
                    last[z.id] = z.x to z.y
                }
                for (z in w.zombies) assertTrue(z.state == ZState.CLIMBING || z.state == ZState.DEAD ||
                    (if (z.state == ZState.INSIDE) w.map.walkable(w.map.tileOf(z.x), w.map.tileOf(z.y)) else w.map.outsideWalk(w.map.tileOf(z.x), w.map.tileOf(z.y))), "seed $seed: zombie ${z.id} ${z.state} in a wall")
            }
            assertTrue(torn, "seed $seed: no board was torn"); assertTrue(attacked, "seed $seed: no zombie reached the player in 120 s")
            assertEquals(0, stuck, "seed $seed: stuck zombies")
        }
    }

    @Test fun clearingARoundStartsTheNextAfterABreak() {
        val w = FpsWorld(3); val p = w.player
        w.run(FpsRules.FIRST_ROUND_DELAY + 0.1f) { p.invulnT = 1e9f; FpsInput(yaw = p.yaw) }
        assertEquals(1, w.round); assertEquals(RoundState.LIVE, w.roundState)
        var t = 0f
        while (w.roundState == RoundState.LIVE && t < 200f) { p.invulnT = 1e9f; for (z in w.zombies.toList()) if (z.alive && z.state != ZState.OUTSIDE) w.damageZombie(z, 9999f, false, false); w.update(DT, FpsInput(yaw = p.yaw)); t += DT }
        assertEquals(RoundState.BREAK, w.roundState); assertEquals(FpsRules.zombieCount(1), p.kills)
        w.run(FpsRules.ROUND_BREAK + 0.2f) { p.invulnT = 1e9f; FpsInput(yaw = p.yaw) }
        assertEquals(2, w.round)
    }

    @Test fun neverMoreThanTheAliveCapAndOnlyOpenRoomsSpawn() {
        val w = FpsWorld(5); val p = w.player
        w.startRound(12)
        repeat(30 * 90) { p.invulnT = 1e9f; w.update(DT, FpsInput(yaw = p.yaw)); assertTrue(w.aliveZombies <= FpsRules.MAX_ALIVE) }
        assertTrue(w.zombies.all { w.map.windows[it.window].zone == 0 }, "only the start room is open")
    }
}

/**
 * A crude scripted player: stays in the start room, shoots the nearest zombie it can see (aiming for the head), knifes what is
 * close, reloads, rebuilds windows when nothing is inside, and buys the Ranger when it can. Measures how far the loop carries.
 */
class FpsAutoPlayTest {
    private fun play(seed: Long): Pair<Int, Int> {
        val w = FpsWorld(seed); val p = w.player; var t = 0f
        val ranger = w.map.props.first { it.gun == FpsGuns.RANGER }
        while (!w.over && t < 1500f) {
            val target = w.zombies.filter { it.alive && (it.state == ZState.INSIDE || it.state == ZState.CLIMBING || it.state == ZState.BREAKING) }
                .filter { w.map.clearPath(p.x, p.y, it.x, it.y, 0f) { a, b -> w.map.stopsBullets(a, b) } }
                .minByOrNull { hypot(it.x - p.x, it.y - p.y) }
            var yaw = p.yaw; var pitch = 0f; var fire = false; var knife = false; var use = false; var mx = 0f; var my = 0f
            if (target != null) {
                val d = hypot(target.x - p.x, target.y - p.y)
                yaw = atan2(target.y - p.y, target.x - p.x); pitch = atan2(1.6f * target.scale - FpsWorld.EYE, d)
                if (d < 1.4f) knife = (t * 30).toInt() % 20 == 0 else fire = true
                if (d < 3f && target.state == ZState.INSIDE) { mx = 0f; my = -1f } // back-pedal
            } else {
                // go back toward the middle of the start room, fix the nearest damaged window, buy the Ranger
                val win = w.map.windows.filter { it.zone == 0 && it.boards < Window.MAX_BOARDS }.minByOrNull { hypot(w.map.centre(it.inX) - p.x, w.map.centre(it.inY) - p.y) }
                val (gx, gy) = when {
                    p.guns.none { it.gun == FpsGuns.RANGER } && p.points >= 500 -> (w.map.centre(ranger.tx) + ranger.fx * 1.6f) to (w.map.centre(ranger.ty) + ranger.fy * 1.6f)
                    win != null -> w.map.centre(win.inX) to w.map.centre(win.inY)
                    else -> w.map.startX to w.map.startY
                }
                val d = hypot(gx - p.x, gy - p.y)
                if (d > 0.4f) { yaw = atan2(gy - p.y, gx - p.x); my = 1f } else use = true
                if (p.gun.mag < p.gun.magSize / 2) use = use // reload below
            }
            val reload = target == null && p.gun.mag < p.gun.magSize
            w.update(DT, FpsInput(mx, my, yaw, pitch, fire, reload, use, knife)); t += DT
        }
        return w.round to p.kills
    }

    @Test fun aSimpleScriptedPlayerSurvivesSeveralRoundsButNotForever() {
        val runs = (1L..6L).map { play(it) }
        println("FPS autoplay (round reached, kills): $runs")
        assertTrue(runs.map { it.first }.average() >= 4.0, "the early rounds should be survivable: $runs")
        assertTrue(runs.all { it.first < 40 }, "the game must get harder: $runs")
    }
}
