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
    EASY(9f, 0.7f, 5f, 420f), NORMAL(7.5f, 0.5f, 7f, 520f), HARD(2.5f, 0.2f, 12f, 650f)
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
    private var advancing = false // hysteresis for "I must move toward the safe zone"
    private var branch = ""
    private var cmx = 0f; private var cmy = 0f; private var commitT = 0f // steering decision we are sticking to
    private var burned = false // we were just outside the zone and have not yet got comfortably back inside
    private var clock = 0f
    private val badLoot = HashMap<Int, Float>() // loot id -> time until which we do not try it again

    // personality and combat memory
    /** 0.35 cautious looter .. 1.0 hunter. Hunters prefer towns for their landing area. */
    val aggression = 0.35f + rng.nextFloat() * 0.65f
    private val gunTaste = BrGuns.ALL.associateWith { 0.75f + rng.nextFloat() * 0.5f } // loadouts differ from bot to bot
    private var home: Pt? = null // the area this bot "dropped" into and loots first
    private var lastHealth = -1f; private var hurtT = 0f

    /** For tests and tuning: a one-line view of what the bot is trying to do. */
    fun debug(): String = "branch=$branch goal=${if (hasGoal) "(${goalX.toInt()},${goalY.toInt()})" else "none"} loot=${goalIsLoot?.kind} path=${path.size}@$pathIdx[${path.drop(pathIdx).take(3).joinToString { "(${it.x.toInt()},${it.y.toInt()})" }}] stuckHits=$stuckHits tgt=${if (tgtKey == Int.MIN_VALUE) "-" else tgtKey}"

    fun think(w: BrWorld, f: Fighter, dt: Float): PlayerInput {
        if (home == null) assignHome(w, f)
        scanT -= dt; lootScanT -= dt; repathT -= dt; strafeT -= dt; aimErrT -= dt; goalAge += dt; clock += dt
        if (hurtT > 0f) hurtT -= dt
        if (commitT > 0f) commitT -= dt
        val health = f.hp + f.shield
        if (lastHealth >= 0f && health < lastHealth - 0.5f && w.inZone(f.x, f.y)) hurtT = 3f // someone is shooting us
        lastHealth = health
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
        val gun = f.weapon.gun
        val engageDist = if (tgtKey < 0 && tgtKey != Int.MIN_VALUE) 330f else gun.range * 1.1f * aggression // zombies: shoot what is close; fighters: depends on temperament
        val engaged = tgt != null && reactT <= 0f && (dist <= engageDist || hurtT > 0f)
        val weak = (f.hp + f.shield) < 0.35f * (f.maxHp + BrWorld.MAX_SHIELD) // hurt badly: break contact (and heal once out of sight)

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
        val rotating = mustRotate(w, f)
        advancing = rotating
        // Once the zone has caught us, keep moving in until we are clearly inside: without this margin the bot steps back
        // over the edge for loot, gets burned, steps in again, and so on every tick.
        val edgeGapNow = w.zoneR - hypot(w.zoneCx - f.x, w.zoneCy - f.y)
        if (outside) burned = true else if (edgeGapNow > EDGE_MARGIN) burned = false
        val unsafe = outside || rotating || burned
        if (unsafe) {
            branch = "unsafe"
            val p = rotateTarget(w, f)
            goalAt(p.x, p.y, 40f)
            val d = follow(w, f, dt); mx = d.first; my = d.second
        } else if (engaged && weak && tgtKey >= 0) {
            branch = "flee"
            val ux = (tx - f.x) / max(dist, 1f); val uy = (ty - f.y) / max(dist, 1f)
            if (strafeT <= 0f) { strafeT = 0.8f + rng.nextFloat() * 0.8f; strafe = if (rng.nextBoolean()) 1f else -1f }
            // run away, weaving a little; if every way out is blocked, stand and shoot instead of shivering
            val s = steer(w, f, -ux * 0.9f - uy * strafe * 0.4f, -uy * 0.9f + ux * strafe * 0.4f)
            mx = s?.first ?: 0f; my = s?.second ?: 0f
        } else if (engaged) {
            branch = "fight"
            val ideal = (gun.range * 0.42f).coerceIn(110f, 380f)
            if (strafeT <= 0f) { strafeT = 0.8f + rng.nextFloat() * 1.0f; strafe = if (rng.nextBoolean()) 1f else -1f }
            val ux = (tx - f.x) / max(dist, 1f); val uy = (ty - f.y) / max(dist, 1f)
            var sx = -uy * strafe; var sy = ux * strafe
            if (dist > ideal + 70f) { mx = ux * 0.8f + sx * 0.5f; my = uy * 0.8f + sy * 0.5f }
            else if (dist < ideal - 70f) { mx = -ux * 0.8f + sx * 0.5f; my = -uy * 0.8f + sy * 0.5f }
            else { mx = sx; my = sy }
            // steer around walls with a committed direction instead of flipping the strafe side every tick
            val s = steer(w, f, mx, my)
            mx = s?.first ?: 0f; my = s?.second ?: 0f
            if (w.map.clearLine(f.x, f.y, tx, ty).not()) { goalAt(tx, ty); val d = follow(w, f, dt); mx = d.first; my = d.second }
        } else if (needsHeal(f)) {
            branch = "heal"
            heal = true // stand still and patch up
            hasGoal = false
        } else {
            branch = "loot"
            if (f.rounds < f.weapon.mag / 2 && !f.reloading) reload = true
            if (lootScanT <= 0f) { lootScanT = 0.5f; chooseLoot(w, f) }
            val l = goalIsLoot
            if (l != null && w.loot.contains(l)) {
                if (l.kind == LootKind.WEAPON && hypot(l.x - f.x, l.y - f.y) < BrWorld.PICKUP_RANGE - 8f) { use = true; goalIsLoot = null; hasGoal = false }
                else { val stand = w.map.nearestFree(l.x, l.y, BrConst.BODY_R + 2f); goalAt(stand.x, stand.y, 3f) } // a body cannot stand ON loot that hugs a wall, but can reach it from here
            } else {
                goalIsLoot = null
                if (!hasGoal || goalAge > 14f || hypot(goalX - f.x, goalY - f.y) < 60f) wander(w, f)
            }
            if (hasGoal) { val d = follow(w, f, dt, if (goalIsLoot != null && goalIsLoot!!.kind != LootKind.WEAPON) 8f else 28f); mx = d.first; my = d.second }
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
            if ((abs(mx) + abs(my)) > 0.2f && moved < 6f) { stuckHits++; unstickT = 0.5f; unstickDir = if (rng.nextBoolean()) 1f else -1f; repathT = 0f; path = emptyList(); if (stuckHits >= 3) { goalIsLoot?.let { badLoot[it.id] = clock + 25f }; hasGoal = false; goalIsLoot = null; stuckHits = 0 } }
            else if (moved > 20f) stuckHits = 0
            checkX = f.x; checkY = f.y; stuckT = 0f
        }
        if (unstickT > 0f) { branch += "+unstick"; unstickT -= dt; val l = hypot(mx, my).let { if (it < 0.01f) 1f else it }; val nx = mx / l; val ny = my / l; mx = -ny * unstickDir + nx * 0.3f; my = nx * unstickDir + ny * 0.3f }

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

    /**
     * Leave for the next circle only when the margin is getting tight: compare when the closing edge will reach this
     * bot with how long the walk to safety takes. Early on bots stay and loot; later they rotate in good time.
     */
    private fun mustRotate(w: BrWorld, f: Fighter): Boolean {
        val outsideBy = hypot(w.nextCx - f.x, w.nextCy - f.y) - w.nextR // > 0: outside the circle we must end up in
        if (outsideBy <= (if (advancing) -110f else -40f)) return false // comfortably inside (hysteresis)
        val edgeGap = w.zoneR - hypot(w.zoneCx - f.x, w.zoneCy - f.y)
        if (edgeGap <= 0f) return true
        val step = BrWorld.ZONES[min(w.zoneIdx, BrWorld.ZONES.size - 1)]
        val remaining = if (w.zoneShrinking) max(1f, step.shrink - w.zoneT) else step.shrink
        val edgeSpeed = max(1f, (w.zoneR - w.nextR) / remaining)
        val eta = (if (w.zoneShrinking) 0f else w.zoneTimeLeft) + edgeGap / edgeSpeed
        val need = max(0f, outsideBy) / (BrWorld.SPEED * 0.7f) + 6f
        return eta < need * 1.3f + (if (advancing) 8f else 0f) // once on the move, keep going a little longer than it took to start
    }

    /** The nearest comfortable spot inside the next circle, so rotating bots arrive spread out rather than piling in the middle. */
    private fun rotateTarget(w: BrWorld, f: Fighter): Pt {
        val dx = f.x - w.nextCx; val dy = f.y - w.nextCy; val d = hypot(dx, dy)
        val reach = min(d, w.nextR * 0.6f)
        val tx = if (d < 1f) w.nextCx else w.nextCx + dx / d * reach; val ty = if (d < 1f) w.nextCy else w.nextCy + dy / d * reach
        return w.map.nearestFree(tx, ty, BrConst.BODY_R + 6f)
    }

    // ---- loot -----------------------------------------------------------------------------------------------------
    private fun weaponScore(wp: BrWeapon): Float {
        val g = wp.gun
        val closeBonus = when (g) { BrGuns.SCATTER -> 1.5f; BrGuns.NOVA -> 1.7f; BrGuns.LANCER -> 1.2f; else -> 1f }
        return wp.dps * (0.5f + g.range / 1400f) * closeBonus * (gunTaste[g] ?: 1f)
    }

    private fun chooseLoot(w: BrWorld, f: Fighter) {
        val cur = weaponScore(f.weapon)
        var best: Loot? = null; var bestV = 0f
        for (l in w.loot) {
            val d = hypot(l.x - f.x, l.y - f.y); if (d > 750f) continue
            if (early(w) && home.let { h -> h != null && hypot(l.x - h.x, l.y - h.y) > 420f }) continue // first minute: stay in my own area
            if ((badLoot[l.id] ?: 0f) > clock) continue
            if (w.zoneR - hypot(w.zoneCx - l.x, w.zoneCy - l.y) < EDGE_MARGIN * 0.7f) continue // not worth hugging the edge for
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

    /**
     * Bots loot close to where they landed. Everyone does so until the zone starts closing; cautious bots keep to their
     * own area for the first two zone stages unless they have to rotate, while hunters roam and look for fights.
     */
    private fun early(w: BrWorld) = (w.zoneIdx == 0 && !w.zoneShrinking) || (aggression < 0.7f && w.zoneIdx < 2 && !advancing)

    /**
     * Picks a direction close to the wanted one that is not blocked by a wall within ~45 px, and sticks to it for a
     * short while so the bot does not dither. Null when every direction is blocked (cornered).
     */
    private fun steer(w: BrWorld, f: Fighter, wx: Float, wy: Float): Pair<Float, Float>? {
        fun clear(vx: Float, vy: Float) = w.map.clearLine(f.x, f.y, f.x + vx * 45f, f.y + vy * 45f, BrConst.BODY_R)
        if (commitT > 0f && clear(cmx, cmy)) return cmx to cmy
        val base = atan2(wy, wx)
        for (da in STEER_FAN) {
            val a = base + da; val vx = cos(a); val vy = sin(a)
            if (clear(vx, vy)) { cmx = vx; cmy = vy; commitT = 0.45f; return vx to vy }
        }
        commitT = 0f
        return null
    }

    /** Called by the world so that bots land in different places. */
    fun setHome(x: Float, y: Float) { home = Pt(x, y) }

    private fun assignHome(w: BrWorld, f: Fighter) {
        val spots = w.map.lootSpots.sortedBy { hypot(it.x - f.x, it.y - f.y) }
        val pool = (if (aggression > 0.65f) spots.take(10).filter { it.tier > 0 }.ifEmpty { spots.take(5) } else spots.take(6))
        val s = pool[rng.nextInt(pool.size)]
        home = Pt(s.x, s.y)
    }

    private fun wander(w: BrWorld, f: Fighter) {
        val h = home
        val useHome = early(w) && h != null
        val cx = if (useHome) h!!.x else f.x; val cy = if (useHome) h!!.y else f.y
        val r = if (useHome) 260f else 320f
        repeat(8) {
            val a = rng.nextFloat() * 2 * PI.toFloat(); val d = r * rng.nextFloat()
            val p = w.map.nearestFree(cx + cos(a) * d, cy + sin(a) * d, BrConst.BODY_R + 4f)
            val inside = w.inZone(p.x, p.y) && (!w.zoneShrinking || hypot(p.x - w.nextCx, p.y - w.nextCy) < w.nextR - 30f)
            if (inside && w.map.nav.isWalkable(p.x, p.y)) { goalX = p.x; goalY = p.y; hasGoal = true; goalAge = 0f; path = emptyList(); return }
        }
        hasGoal = false
    }

    // ---- movement -------------------------------------------------------------------------------------------------
    /** Points the bot at (x, y). [slack] is how far the existing goal may differ before we re-plan (large for moving targets, tiny for loot). */
    private fun goalAt(x: Float, y: Float, slack: Float = 60f) {
        if (!hasGoal || hypot(goalX - x, goalY - y) > slack) { goalX = x; goalY = y; hasGoal = true; goalAge = 0f; path = emptyList(); repathT = 0f }
    }

    /** Steps along a path to the current goal, returning a unit-ish movement vector. */
    private fun follow(w: BrWorld, f: Fighter, dt: Float, arrive: Float = 28f): Pair<Float, Float> {
        if (!hasGoal) return 0f to 0f
        if (hypot(goalX - f.x, goalY - f.y) < arrive) return 0f to 0f
        val direct = w.map.clearLine(f.x, f.y, goalX, goalY, BrConst.BODY_R)
        if (direct) { path = emptyList(); return aimAt(f, goalX, goalY) }
        if (path.isEmpty() || repathT <= 0f) {
            path = w.map.nav.path(f.x, f.y, goalX, goalY) ?: emptyList(); pathIdx = 0; repathT = 1.5f
            if (path.isEmpty()) { hasGoal = false; return 0f to 0f }
        }
        // A waypoint only counts as reached when we are close AND can see it: being 20 px away on the far side of a thin
        // wall is not "there", and skipping ahead from there leads straight into the wall.
        while (pathIdx < path.size - 1 && hypot(path[pathIdx].x - f.x, path[pathIdx].y - f.y) < 26f && w.map.clearLine(f.x, f.y, path[pathIdx].x, path[pathIdx].y, BrConst.BODY_R - 4f)) pathIdx++
        // Lost sight of the waypoint we are heading for (pushed around a corner): plan again from here.
        if (pathIdx < path.size && !w.map.clearLine(f.x, f.y, path[pathIdx].x, path[pathIdx].y, BrConst.BODY_R - 4f) && repathT < 1.0f) { path = emptyList(); repathT = 0f; return 0f to 0f }
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

private const val EDGE_MARGIN = 120f

private val STEER_FAN = floatArrayOf(0f, 0.5f, -0.5f, 1.0f, -1.0f, 1.6f, -1.6f, 2.2f, -2.2f)
