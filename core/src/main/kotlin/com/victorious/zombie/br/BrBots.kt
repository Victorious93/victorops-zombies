package com.victorious.zombie.br

import com.victorious.zombie.logic.Ability
import com.victorious.zombie.sim.PlayerInput
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sign
import kotlin.math.sin
import kotlin.random.Random

/** How good bots are: aim error, reaction time and how fast they can swing their aim. */
enum class BotSkill(val aimErrorDeg: Float, val reactionS: Float, val turnRate: Float, val sight: Float) {
    EASY(9f, 0.7f, 5f, 420f), NORMAL(5f, 0.4f, 8f, 520f), HARD(2.5f, 0.2f, 12f, 650f)
}

/**
 * One bot's decisions. It reads the world like a player would (sight range, line of sight) and returns the same
 * [PlayerInput] a human sends, so bots obey every rule of the sim. Priorities: leave the zone, fight, heal, loot, advance.
 */
class BrBrain(private val skill: BotSkill, seed: Int) {
    private val rng = Random(seed)
    private val sight = skill.sight

    // targeting
    private var scanT = 0f
    private var tgtF: Fighter? = null; private var tgtZ: Zomb? = null
    private var tgtKey = Int.MIN_VALUE
    private var reactT = 0f
    private var lastTx = 0f; private var lastTy = 0f; private var tvx = 0f; private var tvy = 0f
    private var aimAngle = rng.nextFloat() * 2 * PI.toFloat(); private var aimErr = 0f; private var aimErrT = 0f
    private var burstT = 0f; private var pauseT = 0f
    private var strafe = 1f; private var strafeT = 0f

    // navigation
    private var path: List<Pt> = emptyList(); private var pathIdx = 0; private var repathT = 0f
    private var goalX = 0f; private var goalY = 0f; private var hasGoal = false; private var goalAge = 0f; private var goalIsLoot: Loot? = null
    private var stuckT = 0f; private var checkX = 0f; private var checkY = 0f; private var unstickT = 0f; private var unstickDir = 1f; private var stuckHits = 0
    private var lootScanT = 0f

    /** For tests and tuning: a one-line view of what the bot is trying to do. */
    fun debug(): String = "goal=${if (hasGoal) "(${goalX.toInt()},${goalY.toInt()})" else "none"} loot=${goalIsLoot?.kind} path=${path.size}@$pathIdx stuckHits=$stuckHits tgt=${if (tgtKey == Int.MIN_VALUE) "-" else tgtKey}"

    fun think(w: BrWorld, f: Fighter, dt: Float): PlayerInput {
        scanT -= dt; lootScanT -= dt; repathT -= dt; strafeT -= dt; aimErrT -= dt; goalAge += dt
        if (scanT <= 0f) { scanT = 0.12f; scan(w, f) }
        val tgt = currentTarget(w)
        val tx = tgt?.first ?: 0f; val ty = tgt?.second ?: 0f
        val dist = if (tgt != null) hypot(tx - f.x, ty - f.y) else 0f
        if (tgt != null) {
            if (reactT > 0f) reactT -= dt
            val vdt = max(dt, 1e-3f)
            tvx = tvx * 0.7f + (tx - lastTx) / vdt * 0.3f; tvy = tvy * 0.7f + (ty - lastTy) / vdt * 0.3f
            lastTx = tx; lastTy = ty
        }
        val engaged = tgt != null && reactT <= 0f
        val gun = f.weapon.gun

        // ---- aim and fire
        var fire = false
        if (engaged) {
            val lead = dist / gun.bulletSpeed
            val px = tx + tvx.coerceIn(-300f, 300f) * lead * 0.8f; val py = ty + tvy.coerceIn(-300f, 300f) * lead * 0.8f
            if (aimErrT <= 0f) { aimErrT = 0.3f; aimErr = (rng.nextFloat() - 0.5f) * 2f * skill.aimErrorDeg * (PI.toFloat() / 180f) }
            val desired = atan2(py - f.y, px - f.x) + aimErr
            aimAngle = turn(aimAngle, desired, skill.turnRate * dt)
            val off = abs(angleDiff(aimAngle, desired))
            if (burstT > 0f) burstT -= dt else if (pauseT > 0f) pauseT -= dt else { burstT = 0.5f + rng.nextFloat() * 0.8f; pauseT = if (gun.interval < 0.2f) 0.15f + rng.nextFloat() * 0.3f else 0f }
            fire = dist < gun.range * 0.95f && off < 0.12f + 0.05f * (dist / 300f) && pauseT <= 0f && f.rounds > 0 && !f.reloading
            if (burstT <= 0f && pauseT <= 0f) pauseT = 0.2f
        } else if (f.input.aimX != 0f || f.input.aimY != 0f) {
            // idle: keep facing the way we walk
        }

        // ---- where to go
        var mx = 0f; var my = 0f
        var heal = false; var use = false; var reload = false; var ability = false
        val outside = !w.inZone(f.x, f.y)
        val (szx, szy, szr) = safeZone(w)
        val toSafe = hypot(szx - f.x, szy - f.y)
        val unsafe = outside || toSafe > szr - 70f

        if (unsafe) {
            goalAt(w, f, szx, szy, 0f)
            val d = follow(w, f, dt); mx = d.first; my = d.second
        } else if (engaged) {
            val ideal = (gun.range * 0.42f).coerceIn(110f, 380f)
            if (strafeT <= 0f) { strafeT = 0.8f + rng.nextFloat() * 1.0f; strafe = if (rng.nextBoolean()) 1f else -1f }
            val ux = (tx - f.x) / max(dist, 1f); val uy = (ty - f.y) / max(dist, 1f)
            var sx = -uy * strafe; var sy = ux * strafe
            if (dist > ideal + 70f) { mx = ux * 0.8f + sx * 0.5f; my = uy * 0.8f + sy * 0.5f }
            else if (dist < ideal - 70f) { mx = -ux * 0.8f + sx * 0.5f; my = -uy * 0.8f + sy * 0.5f }
            else { mx = sx; my = sy }
            // do not strafe into a wall: try the other way
            if (!w.map.clearLine(f.x, f.y, f.x + mx * 40f, f.y + my * 40f, BrConst.BODY_R)) { strafe = -strafe; strafeT = 0.8f; mx = -mx; my = -my }
            if (w.map.clearLine(f.x, f.y, tx, ty).not()) { goalAt(w, f, tx, ty, 0f); val d = follow(w, f, dt); mx = d.first; my = d.second }
        } else if (needsHeal(f)) {
            heal = true // stand still and patch up
            hasGoal = false
        } else {
            if (f.rounds < f.weapon.mag / 2 && !f.reloading) reload = true
            if (lootScanT <= 0f) { lootScanT = 0.5f; chooseLoot(w, f) }
            val l = goalIsLoot
            if (l != null && w.loot.contains(l)) {
                if (l.kind == LootKind.WEAPON && hypot(l.x - f.x, l.y - f.y) < BrWorld.PICKUP_RANGE - 8f) { use = true; goalIsLoot = null; hasGoal = false }
                else goalAt(w, f, l.x, l.y, 0f)
            } else {
                goalIsLoot = null
                if (!hasGoal || goalAge > 14f || hypot(goalX - f.x, goalY - f.y) < 60f) wander(w, szx, szy, szr)
            }
            if (hasGoal) { val d = follow(w, f, dt); mx = d.first; my = d.second }
        }

        // ---- ability
        if (f.abilityCd <= 0f) {
            when (f.character.ability) {
                Ability.BASS_DROP -> {
                    val near = w.fighters.values.count { it !== f && it.alive && hypot(it.x - f.x, it.y - f.y) < BrWorld.BASS_RADIUS * 0.8f } + w.zombies.count { hypot(it.x - f.x, it.y - f.y) < 150f }
                    if (near >= 2 || (near >= 1 && f.hp < f.maxHp * 0.5f)) ability = true
                }
                Ability.FORTIFY -> if (engaged && dist < 400f && f.hp + f.shield < f.maxHp + 30f) ability = true
            }
        }

        // ---- unstick: if we keep failing to move, nudge sideways and re-plan
        stuckT += dt
        if (stuckT >= 0.7f) {
            val moved = hypot(f.x - checkX, f.y - checkY)
            if ((abs(mx) + abs(my)) > 0.2f && moved < 6f) { stuckHits++; unstickT = 0.5f; unstickDir = if (rng.nextBoolean()) 1f else -1f; repathT = 0f; path = emptyList(); if (stuckHits >= 3) { hasGoal = false; goalIsLoot = null; stuckHits = 0 } }
            else if (moved > 20f) stuckHits = 0
            checkX = f.x; checkY = f.y; stuckT = 0f
        }
        if (unstickT > 0f) { unstickT -= dt; val l = hypot(mx, my).let { if (it < 0.01f) 1f else it }; val nx = mx / l; val ny = my / l; mx = -ny * unstickDir + nx * 0.3f; my = nx * unstickDir + ny * 0.3f }

        val l = hypot(mx, my); if (l > 1f) { mx /= l; my /= l }
        return PlayerInput(mx, my, use, ability, cos(aimAngle), sin(aimAngle), fire, heal, reload)
    }

    // ---- sensing --------------------------------------------------------------------------------------------------
    private fun scan(w: BrWorld, f: Fighter) {
        var bestKey = Int.MIN_VALUE; var bestScore = Float.MAX_VALUE; var bf: Fighter? = null; var bz: Zomb? = null
        for (o in w.fighters.values) {
            if (o === f || !o.alive) continue
            val d = hypot(o.x - f.x, o.y - f.y); if (d > min(sight, f.weapon.gun.range * 1.1f) || d * 0.8f >= bestScore) continue
            if (!w.map.clearLine(f.x, f.y, o.x, o.y)) continue
            bestScore = d * 0.8f; bestKey = o.id; bf = o; bz = null
        }
        for (z in w.zombies) {
            val d = hypot(z.x - f.x, z.y - f.y); if (d > 450f || d * 1.2f >= bestScore) continue
            if (!w.map.clearLine(f.x, f.y, z.x, z.y)) continue
            bestScore = d * 1.2f; bestKey = -z.id - 1; bz = z; bf = null
        }
        if (bestKey != tgtKey) {
            tgtKey = bestKey
            if (bestKey != Int.MIN_VALUE) { reactT = skill.reactionS * (0.7f + rng.nextFloat() * 0.6f); tvx = 0f; tvy = 0f; lastTx = bf?.x ?: bz!!.x; lastTy = bf?.y ?: bz!!.y }
        }
        tgtF = bf; tgtZ = bz
    }

    private fun currentTarget(w: BrWorld): Pair<Float, Float>? {
        tgtF?.let { if (it.alive) return it.x to it.y else { tgtF = null; tgtKey = Int.MIN_VALUE } }
        tgtZ?.let { if (w.zombies.contains(it)) return it.x to it.y else { tgtZ = null; tgtKey = Int.MIN_VALUE } }
        return null
    }

    private fun needsHeal(f: Fighter) = (f.medkits > 0 && f.hp < f.maxHp - 25f) || (f.cells > 0 && f.shield < 50f) || f.healKind != 0

    /** Where the bot wants to be: the circle it will have to be in soon, so it moves early instead of racing the damage. */
    private fun safeZone(w: BrWorld): Triple<Float, Float, Float> =
        if (w.zoneShrinking || w.zoneTimeLeft < 12f) Triple(w.nextCx, w.nextCy, w.nextR) else Triple(w.zoneCx, w.zoneCy, w.zoneR)

    // ---- loot -----------------------------------------------------------------------------------------------------
    private fun weaponScore(wp: BrWeapon): Float {
        val g = wp.gun
        val closeBonus = when (g) { BrGuns.SCATTER -> 1.5f; BrGuns.NOVA -> 1.7f; BrGuns.LANCER -> 1.2f; else -> 1f }
        return wp.dps * (0.5f + g.range / 1400f) * closeBonus
    }

    private fun chooseLoot(w: BrWorld, f: Fighter) {
        val cur = weaponScore(f.weapon)
        var best: Loot? = null; var bestV = 0f
        for (l in w.loot) {
            val d = hypot(l.x - f.x, l.y - f.y); if (d > 750f) continue
            val value = when (l.kind) {
                LootKind.WEAPON -> { val s = weaponScore(l.weapon!!); if (s > cur * 1.15f) (s - cur) / cur * 2f + 0.5f else 0f }
                LootKind.MEDKIT -> if (f.medkits < BrWorld.CARRY) 1.0f - f.medkits * 0.25f else 0f
                LootKind.CELL -> if (f.cells < BrWorld.CARRY) 0.9f - f.cells * 0.25f else 0f
            }
            if (value <= 0f) continue
            // do not walk deep into the Dead Zone for loot
            if (!w.inZone(l.x, l.y) && (!w.zoneShrinking || hypot(l.x - w.nextCx, l.y - w.nextCy) > w.nextR)) continue
            val v = value / (80f + d)
            if (v > bestV) { bestV = v; best = l }
        }
        goalIsLoot = best
    }

    private fun wander(w: BrWorld, cx: Float, cy: Float, r: Float) {
        repeat(6) {
            val a = rng.nextFloat() * 2 * PI.toFloat(); val d = r * 0.7f * rng.nextFloat()
            val p = w.map.nearestFree(cx + cos(a) * d, cy + sin(a) * d, BrConst.BODY_R + 4f)
            if (w.map.nav.isWalkable(p.x, p.y)) { goalX = p.x; goalY = p.y; hasGoal = true; goalAge = 0f; path = emptyList(); return }
        }
    }

    // ---- movement -------------------------------------------------------------------------------------------------
    private fun goalAt(w: BrWorld, f: Fighter, x: Float, y: Float, @Suppress("UNUSED_PARAMETER") slack: Float) {
        if (!hasGoal || hypot(goalX - x, goalY - y) > 60f) { goalX = x; goalY = y; hasGoal = true; goalAge = 0f; path = emptyList(); repathT = 0f }
    }

    /** Steps along a path to the current goal, returning a unit-ish movement vector. */
    private fun follow(w: BrWorld, f: Fighter, dt: Float): Pair<Float, Float> {
        if (!hasGoal) return 0f to 0f
        if (hypot(goalX - f.x, goalY - f.y) < 28f) return 0f to 0f
        val direct = w.map.clearLine(f.x, f.y, goalX, goalY, BrConst.BODY_R)
        if (direct) { path = emptyList(); return aimAt(f, goalX, goalY) }
        if (path.isEmpty() || repathT <= 0f) {
            path = w.map.nav.path(f.x, f.y, goalX, goalY) ?: emptyList(); pathIdx = 0; repathT = 1.5f
            if (path.isEmpty()) { hasGoal = false; return 0f to 0f }
        }
        while (pathIdx < path.size - 1 && hypot(path[pathIdx].x - f.x, path[pathIdx].y - f.y) < 26f) pathIdx++
        if (pathIdx >= path.size) return 0f to 0f
        val p = path[pathIdx]
        return aimAt(f, p.x, p.y)
    }

    private fun aimAt(f: Fighter, x: Float, y: Float): Pair<Float, Float> {
        val d = hypot(x - f.x, y - f.y); return if (d < 1f) 0f to 0f else (x - f.x) / d to (y - f.y) / d
    }

    private fun angleDiff(a: Float, b: Float): Float { var d = (b - a) % (2 * PI.toFloat()); if (d > PI) d -= 2 * PI.toFloat(); if (d < -PI) d += 2 * PI.toFloat(); return d }
    private fun turn(cur: Float, target: Float, maxStep: Float): Float { val d = angleDiff(cur, target); return if (abs(d) <= maxStep) target else cur + sign(d) * maxStep }
}
