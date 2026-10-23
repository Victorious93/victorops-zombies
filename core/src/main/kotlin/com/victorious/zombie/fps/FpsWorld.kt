package com.victorious.zombie.fps

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * One frame of player controls. [moveX] strafes right, [moveY] walks forward (both -1..1). [yaw] / [pitch] are absolute view angles
 * in radians (the screen owns the camera; the sim just uses them). Buttons are "held" states; the sim detects presses itself.
 */
data class FpsInput(
    val moveX: Float = 0f, val moveY: Float = 0f, val yaw: Float = 0f, val pitch: Float = 0f,
    val fire: Boolean = false, val reload: Boolean = false, val use: Boolean = false, val knife: Boolean = false, val swap: Boolean = false,
)

enum class ZState { OUTSIDE, BREAKING, CLIMBING, INSIDE, DEAD }
enum class RoundState { WAITING, LIVE, BREAK }
enum class BoxState { IDLE, ROLLING, READY }

class FpsZombie(val id: Int, var x: Float, var y: Float, val maxHp: Float, val speed: Float, val window: Int, val scale: Float, val look: Int) {
    var hp = maxHp
    var state = ZState.OUTSIDE
    var tearT = 0f; var climbT = 0f
    var attackT = 0f; var attackCd = 0f
    var facing = 0f; var walkPhase = 0f
    var deadT = 0f; var headless = false; var hitT = 0f
    var stuckT = 0f; var checkX = x; var checkY = y; var nudgeT = 0f; var nudgeX = 0f; var nudgeY = 0f
    val alive get() = state != ZState.DEAD
    val attacking get() = attackT > 0f
}

class FpsPlayer(val maxHpBase: Float, val speedMult: Float) {
    var x = 0f; var y = 0f; var yaw = 0f; var pitch = 0f
    var hp = maxHpBase
    val guns = ArrayList<HeldGun>(2)
    var cur = 0
    var fireCd = 0f; var reloadT = 0f; var swapT = 0f; var knifeT = 0f; var knifeCd = 0f
    val perks = LinkedHashSet<Perk>()
    var secondWindBought = 0
    var downT = 0f; var invulnT = 0f; var sinceHurt = 99f
    var points = FpsRules.START_POINTS
    var kills = 0; var headshots = 0; var downs = 0; var pointsEarned = 0
    var moving = 0f
    val gun get() = guns[cur]
    val downed get() = downT > 0f
    val maxHp get() = if (Perk.IRONHIDE in perks) FpsRules.IRONHIDE_HP * maxHpBase / FpsRules.PLAYER_HP else maxHpBase
}

class PowerDrop(val kind: PowerUp, val x: Float, val y: Float) { var t = FpsRules.POWERUP_LIFE }

/** Things the screen reacts to this frame (sound, flashes, popups). Cleared at the start of every [FpsWorld.update]. */
class FpsEvent(val type: Type, val x: Float = 0f, val y: Float = 0f, val z: Float = 0f, val n: Int = 0, val text: String = "", val flag: Boolean = false) {
    enum class Type { SHOT, IMPACT, HIT, KILL, POINTS, HURT, ROUND_START, ROUND_END, BOUGHT, DENIED, POWER_ON, POWERUP_DROP, POWERUP, BOARD_TORN, BOARD_FIXED, DOWN, REVIVED, GAME_OVER, RELOAD, KNIFE, BOX_ROLL, DOOR, GROWL, SWAP, EMPTY }
}

/**
 * Zombies 3D: the headless round-based survival sim (solo). The screen sends [FpsInput] every frame and draws what is here.
 * Classic loop: zombies spawn outside boarded windows of the rooms you have opened, tear the boards down, climb in and chase you.
 * Hits and kills earn points; points buy guns on walls, doors to new rooms, the mystery box, perks (after the power is on) and the
 * forge, which upgrades your gun.
 */
class FpsWorld(
    seed: Long = System.nanoTime(), maxHp: Float = FpsRules.PLAYER_HP, speedMult: Float = 1f, val map: FpsMap = FpsMap(),
    /** False keeps the world in its pre-game wait forever (tests that place their own zombies). */
    private val autoRounds: Boolean = true,
) {
    companion object {
        const val EYE = 1.6f
        const val PLAYER_R = 0.35f; const val ZOMBIE_R = 0.3f
        const val SPEED = 4.6f
        const val REACH = 1.7f
        const val ATTACK_RANGE = 1.05f; const val ATTACK_HIT_RANGE = 1.45f; const val ATTACK_WINDUP = 0.45f; const val ATTACK_COOLDOWN = 0.9f
        const val CLIMB_TIME = 1.1f
        const val REPAIR_TIME = 0.7f
        const val ROLL_TIME = 3.5f; const val BOX_READY_TIME = 10f
        const val DOWN_TIME = 4f
    }

    val rng = Random(seed)
    val player = FpsPlayer(maxHp, speedMult)
    val zombies = ArrayList<FpsZombie>()
    val drops = ArrayList<PowerDrop>()
    val events = ArrayList<FpsEvent>()
    val zoneOpen = BooleanArray(map.zoneCount).also { it[0] = true }

    var round = 0; private set
    var roundState = RoundState.WAITING; private set
    var stateT = FpsRules.FIRST_ROUND_DELAY; private set
    var toSpawn = 0; private set
    private var spawnCd = 0f
    var power = false; private set
    var boxState = BoxState.IDLE; private set
    var boxT = 0f; private set
    var boxGun: FpsGun? = null; private set
    /** Index into [FpsGuns.BOX] shown while the box rolls (it cycles), for the renderer. */
    var boxShow = 0; private set
    var instaT = 0f; private set
    var doubleT = 0f; private set
    var over = false; private set
    var time = 0f; private set
    /** What USE would do right now ("" = nothing). */
    var prompt = ""; private set
    /** True when [prompt] can be afforded / is available (the screen greys it out otherwise). */
    var promptOk = false; private set
    private var nextId = 1
    private var dropsThisRound = 0
    private var boardPointsThisRound = 0
    private var repairT = 0f
    private var prevUse = false; private var prevKnife = false; private var prevSwap = false; private var prevReload = false
    private var flowTile = -1
    private val tmp = FloatArray(2)

    init {
        player.x = map.startX; player.y = map.startY; player.yaw = -PI.toFloat() / 2
        player.guns += HeldGun(FpsGuns.PISTOL)
    }

    val aliveZombies: Int get() = zombies.count { it.alive }

    fun update(dtIn: Float, input: FpsInput) {
        events.clear()
        if (over) return
        val dt = min(dtIn, 0.05f)
        time += dt
        updatePlayer(dt, input)
        val pt = map.tileOf(player.y) * map.w + map.tileOf(player.x)
        if (pt != flowTile) { flowTile = pt; map.flowTo(map.tileOf(player.x), map.tileOf(player.y)) }
        for (z in zombies) updateZombie(z, dt)
        separate()
        zombies.removeAll { it.state == ZState.DEAD && it.deadT > 2.5f }
        updateRound(dt)
        updateDrops(dt)
        updateBox(dt)
        if (instaT > 0f) instaT -= dt
        if (doubleT > 0f) doubleT -= dt
        computePrompt()
    }

    private fun emit(type: FpsEvent.Type, x: Float = 0f, y: Float = 0f, z: Float = 0f, n: Int = 0, text: String = "", flag: Boolean = false) {
        if (events.size < 256) events += FpsEvent(type, x, y, z, n, text, flag)
    }

    private fun addPoints(n: Int) {
        val v = if (doubleT > 0f) n * 2 else n
        player.points += v; player.pointsEarned += v
        emit(FpsEvent.Type.POINTS, n = v)
    }

    // ---- player ----------------------------------------------------------------------------------------------------
    private fun updatePlayer(dt: Float, inp: FpsInput) {
        val p = player
        p.yaw = inp.yaw; p.pitch = inp.pitch.coerceIn(-1.35f, 1.35f)
        p.sinceHurt += dt
        if (p.invulnT > 0f) p.invulnT -= dt
        if (p.downed) {
            p.downT -= dt
            if (p.downT <= 0f) { p.downT = 0f; p.hp = p.maxHp; p.invulnT = 3f; pushZombiesAway(3f); emit(FpsEvent.Type.REVIVED) }
            prevUse = inp.use; prevKnife = inp.knife; prevSwap = inp.swap; prevReload = inp.reload
            return
        }
        if (p.sinceHurt > 3.5f && p.hp < p.maxHp) p.hp = min(p.maxHp, p.hp + 70f * dt)
        if (p.hp > p.maxHp) p.hp = p.maxHp

        // movement
        var mx = inp.moveX; var my = inp.moveY
        val ml = hypot(mx, my); if (ml > 1f) { mx /= ml; my /= ml }
        val fx = cos(p.yaw); val fy = sin(p.yaw)
        val vx = fx * my - fy * mx; val vy = fy * my + fx * mx
        val speed = SPEED * p.speedMult * (if (p.reloadT > 0f || inp.fire) 0.85f else 1f)
        p.moving = min(1f, hypot(vx, vy))
        map.resolve(p.x + vx * speed * dt, p.y + vy * speed * dt, PLAYER_R, tmp) { tx, ty -> !map.walkable(tx, ty) }
        p.x = tmp[0]; p.y = tmp[1]
        // zombies are solid: step back out of any we walked into, then make sure that did not push us into a wall
        for (z in zombies) {
            if (z.state != ZState.INSIDE && z.state != ZState.CLIMBING) continue
            val dx = p.x - z.x; val dy = p.y - z.y; val d = hypot(dx, dy); val m = PLAYER_R + ZOMBIE_R * z.scale
            if (d < m && d > 1e-4f) { p.x = z.x + dx / d * m; p.y = z.y + dy / d * m }
        }
        map.resolve(p.x, p.y, PLAYER_R, tmp) { tx, ty -> !map.walkable(tx, ty) }
        p.x = tmp[0]; p.y = tmp[1]

        // weapons
        p.fireCd -= dt; p.knifeCd -= dt
        if (p.knifeT > 0f) p.knifeT -= dt
        if (p.swapT > 0f) p.swapT -= dt
        val g = p.gun
        if (p.reloadT > 0f) {
            p.reloadT -= dt
            if (p.reloadT <= 0f) { val need = g.magSize - g.mag; val take = min(need, g.reserve); g.mag += take; g.reserve -= take }
        }
        if (inp.swap && !prevSwap && p.guns.size > 1) { p.cur = (p.cur + 1) % p.guns.size; p.reloadT = 0f; p.swapT = 0.45f; emit(FpsEvent.Type.SWAP) }
        if (inp.knife && !prevKnife && p.knifeCd <= 0f) knife()
        val wantReload = inp.reload && !prevReload
        val gg = p.gun
        if ((wantReload || (inp.fire && gg.mag == 0)) && p.reloadT <= 0f && gg.mag < gg.magSize && gg.reserve > 0) startReload()
        if (inp.fire && p.fireCd <= 0f && p.reloadT <= 0f && p.swapT <= 0f && p.knifeT <= 0f) {
            if (gg.mag > 0) shoot() else if (gg.reserve == 0 && p.fireCd <= 0f) { p.fireCd = 0.4f; emit(FpsEvent.Type.EMPTY) }
        }
        // use
        val pressed = inp.use && !prevUse
        interact(pressed, inp.use, dt)
        prevUse = inp.use; prevKnife = inp.knife; prevSwap = inp.swap; prevReload = inp.reload
    }

    private fun startReload() {
        val p = player
        p.reloadT = p.gun.gun.reload * (if (Perk.QUICKHAND in p.perks) 0.5f else 1f)
        emit(FpsEvent.Type.RELOAD)
    }

    fun hurtPlayer(dmg: Float, fromX: Float, fromY: Float) {
        val p = player
        if (p.downed || p.invulnT > 0f || over) return
        p.hp -= dmg; p.sinceHurt = 0f
        emit(FpsEvent.Type.HURT, fromX, fromY, n = dmg.toInt())
        if (p.hp > 0f) return
        p.hp = 0f; p.downs++
        if (Perk.SECOND_WIND in p.perks) {
            p.perks.remove(Perk.SECOND_WIND); p.downT = DOWN_TIME; p.reloadT = 0f
            emit(FpsEvent.Type.DOWN)
        } else {
            over = true
            emit(FpsEvent.Type.GAME_OVER, n = round)
        }
    }

    private fun pushZombiesAway(r: Float) {
        for (z in zombies) {
            if (z.state != ZState.INSIDE) continue
            val dx = z.x - player.x; val dy = z.y - player.y; val d = hypot(dx, dy)
            if (d < r && d > 1e-3f) { map.resolve(z.x + dx / d * (r - d), z.y + dy / d * (r - d), ZOMBIE_R, tmp) { tx, ty -> !map.walkable(tx, ty) }; z.x = tmp[0]; z.y = tmp[1]; z.attackT = 0f }
        }
    }

    // ---- shooting ----------------------------------------------------------------------------------------------------
    private class RayHit(var t: Float = 0f, var z: FpsZombie? = null, var head: Boolean = false)
    private val hits = ArrayList<RayHit>(); private val hitPool = ArrayList<RayHit>()

    private fun shoot() {
        val p = player; val g = p.gun; val gun = g.gun
        g.mag--
        p.fireCd = gun.interval * (if (Perk.RAPIDFIRE in p.perks) 0.75f else 1f)
        emit(FpsEvent.Type.SHOT, n = gun.shape)
        val spread = gun.spreadDeg * (PI.toFloat() / 180f) * (if (p.moving > 0.3f) 1.5f else 1f)
        repeat(gun.pellets) {
            val yaw = p.yaw + (rng.nextFloat() - 0.5f) * 2f * spread
            val pitch = p.pitch + (rng.nextFloat() - 0.5f) * 2f * spread
            fireRay(yaw, pitch, g)
        }
        if (g.mag == 0 && g.reserve > 0) startReload()
    }

    /** One bullet: the nearest zombies along the ray (head or body) up to the first wall, floor or ceiling. */
    private fun fireRay(yaw: Float, pitch: Float, g: HeldGun) {
        val p = player; val gun = g.gun
        val cp = cos(pitch); val dx = cos(yaw) * cp; val dy = sin(yaw) * cp; val dz = sin(pitch)
        val horiz = max(1e-4f, cp)
        var tEnd = map.cast(p.x, p.y, cos(yaw), sin(yaw), gun.range * horiz) { tx, ty -> map.stopsBullets(tx, ty) } / horiz
        if (dz < -1e-4f) tEnd = min(tEnd, EYE / -dz)
        if (dz > 1e-4f) tEnd = min(tEnd, (FpsMap.WALL_H - EYE) / dz)
        tEnd = min(tEnd, gun.range)
        hits.clear()
        for (z in zombies) {
            if (!z.alive) continue
            val t = rayZombie(p.x, EYE, p.y, dx, dz, dy, z, tEnd) ?: continue
            val h = if (hitPool.isEmpty()) RayHit() else hitPool.removeAt(hitPool.size - 1)
            h.t = t; h.z = z; h.head = lastHead; hits += h
        }
        hits.sortBy { it.t }
        var left = gun.pierce + 1
        var impactT = tEnd; var flesh = false
        for (h in hits) {
            if (left <= 0) break
            val z = h.z!!
            if (!z.alive) continue
            // shotgun pellets lose damage with distance
            val fall = if (gun.pellets > 1) (1f - h.t / gun.range).coerceIn(0.25f, 1f) else 1f
            damageZombie(z, g.damage * fall * (if (h.head) gun.headMult else 1f), h.head, knife = false)
            impactT = h.t; flesh = true
            left--
        }
        for (h in hits) { h.z = null; hitPool += h }
        val ix = p.x + dx * impactT; val iy = p.y + dy * impactT; val iz = EYE + dz * impactT
        emit(FpsEvent.Type.IMPACT, ix, iy, iz, flag = flesh)
        if (gun.splash > 0f) {
            for (z in zombies) {
                if (!z.alive) continue
                val d = hypot(z.x - ix, z.y - iy); if (d > gun.splash) continue
                damageZombie(z, g.damage * (1f - 0.5f * d / gun.splash), head = false, knife = false)
            }
        }
    }

    private var lastHead = false

    /** Ray against a zombie: a head sphere and a body cylinder. Sets [lastHead]. Coordinates: (x, up, y). */
    private fun rayZombie(ox: Float, oh: Float, oy: Float, dx: Float, dh: Float, dy: Float, z: FpsZombie, maxT: Float): Float? {
        val s = z.scale
        val lean = if (z.state == ZState.CLIMBING) 0.85f else 1f
        // head
        val hy = 1.62f * s * lean; val hr = 0.2f * s
        val cx = ox - z.x; val ch = oh - hy; val cy = oy - z.y
        val b = cx * dx + ch * dh + cy * dy; val c = cx * cx + ch * ch + cy * cy - hr * hr
        val disc = b * b - c
        var best = Float.MAX_VALUE; var head = false
        if (disc >= 0f) { val t = -b - sqrt(disc); if (t > 0f && t < maxT) { best = t; head = true } }
        // body (vertical cylinder in the x/y plane)
        val br = 0.32f * s; val top = 1.45f * s * lean
        val a2 = dx * dx + dy * dy
        if (a2 > 1e-6f) {
            val b2 = (ox - z.x) * dx + (oy - z.y) * dy; val c2 = (ox - z.x) * (ox - z.x) + (oy - z.y) * (oy - z.y) - br * br
            val d2 = b2 * b2 - a2 * c2
            if (d2 >= 0f) {
                val t = (-b2 - sqrt(d2)) / a2
                val h = oh + dh * t
                if (t > 0f && t < maxT && h in 0f..top && t < best) { best = t; head = false }
            }
        }
        lastHead = head
        return if (best == Float.MAX_VALUE) null else best
    }

    private fun knife() {
        val p = player
        p.knifeCd = FpsRules.KNIFE_INTERVAL; p.knifeT = 0.35f
        var target: FpsZombie? = null; var bd = FpsRules.KNIFE_RANGE
        for (z in zombies) {
            if (!z.alive || z.state == ZState.OUTSIDE) continue
            val dx = z.x - p.x; val dy = z.y - p.y; val d = hypot(dx, dy) - ZOMBIE_R * z.scale
            if (d > bd) continue
            if (abs(angleDiff(p.yaw, atan2(dy, dx))) > 0.75f) continue
            bd = d; target = z
        }
        emit(FpsEvent.Type.KNIFE, flag = target != null)
        if (target != null) damageZombie(target, FpsRules.KNIFE_DAMAGE, head = false, knife = true)
    }

    fun damageZombie(z: FpsZombie, dmgIn: Float, head: Boolean, knife: Boolean) {
        if (!z.alive) return
        val dmg = if (instaT > 0f) z.hp else dmgIn
        z.hp -= dmg; z.hitT = 0.15f
        if (z.hp > 0f) {
            addPoints(FpsRules.HIT_POINTS)
            emit(FpsEvent.Type.HIT, z.x, z.y, flag = head)
            return
        }
        z.state = ZState.DEAD; z.deadT = 0f; z.headless = head && !knife; z.attackT = 0f
        player.kills++; if (head && !knife) player.headshots++
        addPoints(when { knife -> FpsRules.KNIFE_KILL_POINTS; head -> FpsRules.HEADSHOT_KILL_POINTS; else -> FpsRules.KILL_POINTS })
        emit(FpsEvent.Type.KILL, z.x, z.y, n = z.id, flag = head)
        maybeDrop(z)
    }

    private fun maybeDrop(z: FpsZombie) {
        if (dropsThisRound >= FpsRules.POWERUPS_PER_ROUND || z.state == ZState.OUTSIDE || rng.nextFloat() >= FpsRules.POWERUP_CHANCE) return
        if (!map.walkable(map.tileOf(z.x), map.tileOf(z.y))) return
        var kind = PowerUp.values()[rng.nextInt(PowerUp.values().size)]
        if (kind == PowerUp.CARPENTER && map.windows.all { it.boards == Window.MAX_BOARDS }) kind = PowerUp.MAX_AMMO
        drops += PowerDrop(kind, z.x, z.y); dropsThisRound++
        emit(FpsEvent.Type.POWERUP_DROP, z.x, z.y, text = kind.title)
    }

    // ---- zombies ---------------------------------------------------------------------------------------------------
    private fun spawnZombie() {
        val p = player
        // the windows of open rooms, nearest to the player first; pick among the closest few so pressure comes from around you
        val open = map.windows.filter { zoneOpen[it.zone] }.sortedBy { hypot(map.centre(it.tx) - p.x, map.centre(it.ty) - p.y) }
        if (open.isEmpty()) return
        val win = open[rng.nextInt(min(3, open.size))]
        val field = map.outsideFlow[win.id]
        var sx = map.centre(win.outX); var sy = map.centre(win.outY)
        val cands = ArrayList<Int>()
        for (i in field.indices) if (field[i] in 2..4) cands += i
        if (cands.isNotEmpty()) { val i = cands[rng.nextInt(cands.size)]; sx = map.centre(i % map.w) + (rng.nextFloat() - 0.5f) * 0.8f; sy = map.centre(i / map.w) + (rng.nextFloat() - 0.5f) * 0.8f }
        val r = rng.nextFloat()
        val base = when { r < FpsRules.runShare(round) -> 4.0f; r < FpsRules.jogShare(round) -> 2.6f; else -> 1.3f }
        val z = FpsZombie(nextId++, sx, sy, FpsRules.zombieHealth(round), base * (0.9f + rng.nextFloat() * 0.2f), win.id, 0.92f + rng.nextFloat() * 0.16f, rng.nextInt(1 shl 20))
        z.walkPhase = rng.nextFloat() * 6f
        zombies += z
        toSpawn--
        if (rng.nextFloat() < 0.4f) emit(FpsEvent.Type.GROWL, sx, sy)
    }

    /** The spot just outside a window where zombies stand to tear boards, and the spot just inside where they land. */
    private fun approach(win: Window, out: Boolean, res: FloatArray) {
        val dx = (win.tx - win.outX).toFloat(); val dy = (win.ty - win.outY).toFloat()
        val cx = map.centre(win.tx); val cy = map.centre(win.ty)
        val k = FpsMap.CELL / 2 + (if (out) 0.4f else 0.55f)
        res[0] = if (out) cx - dx * k else cx + dx * k; res[1] = if (out) cy - dy * k else cy + dy * k
    }
    private val ap = FloatArray(2)

    private fun updateZombie(z: FpsZombie, dt: Float) {
        if (z.hitT > 0f) z.hitT -= dt
        if (z.state == ZState.DEAD) { z.deadT += dt; return }
        if (z.attackCd > 0f) z.attackCd -= dt
        val p = player
        val win = map.windows[z.window]
        val pd = hypot(p.x - z.x, p.y - z.y)
        when (z.state) {
            ZState.OUTSIDE -> {
                approach(win, true, ap)
                val f = map.outsideFlow[win.id]
                val tx = map.tileOf(z.x); val ty = map.tileOf(z.y)
                var gx = ap[0]; var gy = ap[1]
                val here = if (map.inside(tx, ty)) f[ty * map.w + tx] else -1
                if (here > 0) { // next outside tile toward the window
                    var bx = tx; var by = ty; var bv = here
                    for (k in 0 until 4) { val nx = tx + DXS[k]; val ny = ty + DYS[k]; if (!map.inside(nx, ny)) continue; val v = f[ny * map.w + nx]; if (v in 0 until bv) { bv = v; bx = nx; by = ny } }
                    if (bv < here) { gx = map.centre(bx); gy = map.centre(by) }
                }
                moveToward(z, gx, gy, z.speed, dt)
                map.resolve(z.x, z.y, ZOMBIE_R, tmp) { a, b -> !map.outsideWalk(a, b) }; z.x = tmp[0]; z.y = tmp[1]
                if (hypot(ap[0] - z.x, ap[1] - z.y) < 0.6f) { z.state = ZState.BREAKING; z.tearT = 0f }
            }
            ZState.BREAKING -> {
                approach(win, true, ap)
                if (hypot(ap[0] - z.x, ap[1] - z.y) > 0.3f) moveToward(z, ap[0], ap[1], 1.2f, dt)
                z.facing = atan2(map.centre(win.ty) - z.y, map.centre(win.tx) - z.x)
                // a player standing at the window gets swiped through the gap
                if (pd < 1.9f && win.boards < Window.MAX_BOARDS) tryAttack(z, pd, dt, 1.9f)
                else if (win.boards > 0) {
                    // only the zombie closest to the window tears; the rest wait their turn
                    val first = zombies.none { o -> o !== z && o.state == ZState.BREAKING && o.window == z.window && hypot(ap[0] - o.x, ap[1] - o.y) < hypot(ap[0] - z.x, ap[1] - z.y) }
                    if (first) {
                        z.tearT += dt
                        if (z.tearT >= FpsRules.tearTime(round)) { z.tearT = 0f; win.boards--; emit(FpsEvent.Type.BOARD_TORN, map.centre(win.tx), map.centre(win.ty), n = win.id) }
                    }
                } else if (zombies.none { it.state == ZState.CLIMBING && it.window == z.window }) { z.state = ZState.CLIMBING; z.climbT = 0f; z.attackT = 0f }
            }
            ZState.CLIMBING -> {
                z.climbT += dt
                val k = (z.climbT / CLIMB_TIME).coerceIn(0f, 1f)
                approach(win, true, ap); val ox = ap[0]; val oy = ap[1]
                approach(win, false, ap)
                z.x = ox + (ap[0] - ox) * k; z.y = oy + (ap[1] - oy) * k
                z.facing = atan2(ap[1] - oy, ap[0] - ox)
                if (k >= 1f) { z.state = ZState.INSIDE; z.checkX = z.x; z.checkY = z.y; z.stuckT = 0f }
            }
            ZState.INSIDE -> {
                if (p.downed) { z.attackT = 0f; return }
                if (z.attackT > 0f || pd < ATTACK_RANGE + ZOMBIE_R * (z.scale - 1f)) { z.facing = atan2(p.y - z.y, p.x - z.x); tryAttack(z, pd, dt, ATTACK_HIT_RANGE); return }
                var gx = p.x; var gy = p.y
                val direct = pd < 16f && map.clearPath(z.x, z.y, p.x, p.y, ZOMBIE_R) { a, b -> !map.walkable(a, b) }
                if (!direct) {
                    val tx = map.tileOf(z.x); val ty = map.tileOf(z.y)
                    val here = if (map.inside(tx, ty)) map.flow[ty * map.w + tx] else -1
                    if (here > 0) {
                        var bv = here; var bx = tx; var by = ty
                        for (ddy in -1..1) for (ddx in -1..1) {
                            if (ddx == 0 && ddy == 0) continue
                            val nx = tx + ddx; val ny = ty + ddy
                            if (!map.inside(nx, ny)) continue
                            if (ddx != 0 && ddy != 0 && (!map.walkable(tx + ddx, ty) || !map.walkable(tx, ty + ddy))) continue
                            val v = map.flow[ny * map.w + nx]
                            if (v in 0 until bv) { bv = v; bx = nx; by = ny }
                        }
                        gx = map.centre(bx); gy = map.centre(by)
                    }
                }
                if (z.nudgeT > 0f) { z.nudgeT -= dt; gx = z.x + z.nudgeX; gy = z.y + z.nudgeY }
                moveToward(z, gx, gy, z.speed, dt)
                map.resolve(z.x, z.y, ZOMBIE_R, tmp) { a, b -> !map.walkable(a, b) }; z.x = tmp[0]; z.y = tmp[1]
                // stuck: barely moved for a while although not attacking -> walk sideways for a moment
                z.stuckT += dt
                if (z.stuckT >= 3f) {
                    if (hypot(z.x - z.checkX, z.y - z.checkY) < 0.4f) { val a = rng.nextFloat() * 2f * PI.toFloat(); z.nudgeX = cos(a) * 2f; z.nudgeY = sin(a) * 2f; z.nudgeT = 0.6f }
                    z.stuckT = 0f; z.checkX = z.x; z.checkY = z.y
                }
            }
            ZState.DEAD -> {}
        }
    }

    private fun tryAttack(z: FpsZombie, pd: Float, dt: Float, hitRange: Float) {
        if (z.attackT > 0f) {
            z.attackT -= dt
            if (z.attackT <= 0f) { z.attackCd = ATTACK_COOLDOWN; if (pd <= hitRange) hurtPlayer(FpsRules.ZOMBIE_HIT, z.x, z.y) }
        } else if (z.attackCd <= 0f) { z.attackT = ATTACK_WINDUP; if (rng.nextFloat() < 0.5f) emit(FpsEvent.Type.GROWL, z.x, z.y) }
    }

    private fun moveToward(z: FpsZombie, gx: Float, gy: Float, speed: Float, dt: Float) {
        val dx = gx - z.x; val dy = gy - z.y; val d = hypot(dx, dy)
        if (d < 1e-3f) return
        val step = min(d, speed * dt)
        z.x += dx / d * step; z.y += dy / d * step
        // turn smoothly toward the walking direction
        z.facing += angleDiff(z.facing, atan2(dy, dx)) * min(1f, 8f * dt)
        z.walkPhase += step * 3.2f
    }

    private fun separate() {
        val n = zombies.size
        for (i in 0 until n) {
            val a = zombies[i]
            if (a.state == ZState.DEAD || a.state == ZState.CLIMBING) continue
            for (j in i + 1 until n) {
                val b = zombies[j]
                if (b.state == ZState.DEAD || b.state == ZState.CLIMBING || (a.state == ZState.INSIDE) != (b.state == ZState.INSIDE)) continue
                val dx = b.x - a.x; val dy = b.y - a.y; val d2 = dx * dx + dy * dy; val m = ZOMBIE_R * 1.8f
                if (d2 >= m * m) continue
                val d = sqrt(d2); val nx = if (d > 1e-4f) dx / d else 1f; val ny = if (d > 1e-4f) dy / d else 0f
                val push = (m - d) / 2f
                a.x -= nx * push; a.y -= ny * push; b.x += nx * push; b.y += ny * push
            }
        }
        val p = player
        for (z in zombies) {
            when (z.state) {
                ZState.INSIDE -> {
                    val dx = z.x - p.x; val dy = z.y - p.y; val d = hypot(dx, dy); val m = PLAYER_R + ZOMBIE_R * z.scale
                    if (d < m && d > 1e-4f) { z.x = p.x + dx / d * m; z.y = p.y + dy / d * m }
                    map.resolve(z.x, z.y, ZOMBIE_R, tmp) { a, b -> !map.walkable(a, b) }; z.x = tmp[0]; z.y = tmp[1]
                }
                ZState.OUTSIDE, ZState.BREAKING -> { map.resolve(z.x, z.y, ZOMBIE_R, tmp) { a, b -> !map.outsideWalk(a, b) }; z.x = tmp[0]; z.y = tmp[1] }
                else -> {}
            }
        }
    }

    // ---- rounds ----------------------------------------------------------------------------------------------------
    private fun updateRound(dt: Float) {
        when (roundState) {
            RoundState.WAITING, RoundState.BREAK -> { if (!autoRounds && roundState == RoundState.WAITING) return; stateT -= dt; if (stateT <= 0f) startRound(round + 1) }
            RoundState.LIVE -> {
                spawnCd -= dt
                if (toSpawn > 0 && spawnCd <= 0f && aliveZombies < FpsRules.MAX_ALIVE) { spawnZombie(); spawnCd = FpsRules.spawnInterval(round) }
                if (toSpawn <= 0 && aliveZombies == 0) { roundState = RoundState.BREAK; stateT = FpsRules.ROUND_BREAK; emit(FpsEvent.Type.ROUND_END, n = round) }
            }
        }
    }

    fun startRound(n: Int) {
        round = n; roundState = RoundState.LIVE
        toSpawn = FpsRules.zombieCount(n); spawnCd = 1.2f
        dropsThisRound = 0; boardPointsThisRound = 0
        emit(FpsEvent.Type.ROUND_START, n = n)
    }

    // ---- power-ups -------------------------------------------------------------------------------------------------
    private fun updateDrops(dt: Float) {
        val it = drops.iterator()
        while (it.hasNext()) {
            val d = it.next(); d.t -= dt
            if (d.t <= 0f) { it.remove(); continue }
            if (!player.downed && hypot(d.x - player.x, d.y - player.y) < 1.3f) { it.remove(); applyPowerUp(d.kind) }
        }
    }

    fun applyPowerUp(k: PowerUp) {
        emit(FpsEvent.Type.POWERUP, text = k.title, n = k.ordinal)
        when (k) {
            PowerUp.MAX_AMMO -> for (g in player.guns) g.reserve = g.reserveMax
            PowerUp.INSTA_KILL -> instaT = FpsRules.POWERUP_TIME
            PowerUp.DOUBLE_POINTS -> doubleT = FpsRules.POWERUP_TIME
            PowerUp.NUKE -> {
                for (z in zombies) if (z.alive) { z.state = ZState.DEAD; z.deadT = 0f; z.attackT = 0f; player.kills++ }
                addPoints(FpsRules.NUKE_POINTS)
            }
            PowerUp.CARPENTER -> { for (w in map.windows) w.boards = Window.MAX_BOARDS; addPoints(FpsRules.CARPENTER_POINTS) }
        }
    }

    // ---- box -------------------------------------------------------------------------------------------------------
    private fun updateBox(dt: Float) {
        when (boxState) {
            BoxState.ROLLING -> {
                boxT -= dt
                boxShow = ((ROLL_TIME - boxT) * (6f - 4f * (1f - boxT / ROLL_TIME))).toInt() % FpsGuns.BOX.size
                if (boxT <= 0f) {
                    val held = player.guns.map { it.gun }
                    val pool = FpsGuns.BOX.filter { it !in held }
                    boxGun = pool[rng.nextInt(pool.size)]
                    boxShow = FpsGuns.BOX.indexOf(boxGun)
                    boxState = BoxState.READY; boxT = BOX_READY_TIME
                }
            }
            BoxState.READY -> { boxT -= dt; if (boxT <= 0f) { boxState = BoxState.IDLE; boxGun = null } }
            BoxState.IDLE -> {}
        }
    }

    // ---- interaction -----------------------------------------------------------------------------------------------
    private enum class Act { NONE, WALL, DOOR, BOX, PERK, POWER, FORGE, WINDOW }
    private var act = Act.NONE; private var actProp: Prop? = null; private var actDoor: Door? = null; private var actWin: Window? = null

    /** Finds the nearest usable thing within reach (props by their front face, doors and windows by their tile centre). */
    private fun findTarget() {
        act = Act.NONE; actProp = null; actDoor = null; actWin = null
        val p = player; var best = Float.MAX_VALUE
        for (pr in map.props) {
            if (!zoneOpen[pr.zone]) continue
            val fx = map.centre(pr.tx) + pr.fx * FpsMap.CELL / 2; val fy = map.centre(pr.ty) + pr.fy * FpsMap.CELL / 2
            val d = hypot(fx - p.x, fy - p.y)
            if (d < REACH && d < best) { best = d; actProp = pr; act = when (pr.kind) { PropKind.WALL_BUY -> Act.WALL; PropKind.BOX -> Act.BOX; PropKind.PERK -> Act.PERK; PropKind.POWER -> Act.POWER; PropKind.FORGE -> Act.FORGE } }
        }
        for (d in map.doors) {
            if (d.open) continue
            val dist = hypot(map.centre(d.tx) - p.x, map.centre(d.ty) - p.y) - FpsMap.CELL / 2
            if (dist < REACH - 0.6f && dist < best) { best = dist; actDoor = d; actProp = null; act = Act.DOOR }
        }
        for (w in map.windows) {
            if (!zoneOpen[w.zone] || w.boards >= Window.MAX_BOARDS) continue
            val dist = hypot(map.centre(w.tx) - p.x, map.centre(w.ty) - p.y) - FpsMap.CELL / 2
            if (dist < REACH - 0.6f && dist < best) { best = dist; actWin = w; actProp = null; actDoor = null; act = Act.WINDOW }
        }
    }

    private fun interact(pressed: Boolean, held: Boolean, dt: Float) {
        findTarget()
        val p = player
        if (act != Act.WINDOW) repairT = 0f
        when (act) {
            Act.NONE -> {}
            Act.WINDOW -> if (held) {
                val w = actWin!!
                repairT += dt
                if (repairT >= REPAIR_TIME) {
                    repairT = 0f; w.boards++
                    emit(FpsEvent.Type.BOARD_FIXED, map.centre(w.tx), map.centre(w.ty), n = w.id)
                    if (boardPointsThisRound < FpsRules.BOARD_POINTS_CAP) { boardPointsThisRound += FpsRules.BOARD_POINTS; addPoints(FpsRules.BOARD_POINTS) }
                }
            }
            Act.DOOR -> if (pressed) { val d = actDoor!!; if (pay(d.cost)) { d.open = true; zoneOpen[d.zoneA] = true; zoneOpen[d.zoneB] = true; flowTile = -1; emit(FpsEvent.Type.DOOR, map.centre(d.tx), map.centre(d.ty)) } }
            Act.WALL -> if (pressed) {
                val gun = actProp!!.gun!!
                val owned = p.guns.firstOrNull { it.gun == gun }
                if (owned != null) { if (owned.reserve < owned.reserveMax && pay(ammoCost(owned))) { owned.refill(); emit(FpsEvent.Type.BOUGHT, text = "Ammo") } }
                else if (pay(gun.cost)) giveGun(HeldGun(gun))
            }
            Act.BOX -> if (pressed) when (boxState) {
                BoxState.IDLE -> if (pay(FpsRules.BOX_COST)) { boxState = BoxState.ROLLING; boxT = ROLL_TIME; emit(FpsEvent.Type.BOX_ROLL) }
                BoxState.READY -> { val g = boxGun!!; giveGun(HeldGun(g)); boxGun = null; boxState = BoxState.IDLE }
                BoxState.ROLLING -> {}
            }
            Act.PERK -> if (pressed) {
                val perk = actProp!!.perk!!
                if ((!perk.needsPower || power) && perk !in p.perks && !(perk == Perk.SECOND_WIND && p.secondWindBought >= FpsRules.SECOND_WIND_USES) && pay(perk.cost)) {
                    p.perks += perk; if (perk == Perk.SECOND_WIND) p.secondWindBought++
                    if (perk == Perk.IRONHIDE) p.hp = p.maxHp
                    emit(FpsEvent.Type.BOUGHT, text = perk.title)
                }
            }
            Act.POWER -> if (pressed && !power) { power = true; emit(FpsEvent.Type.POWER_ON) }
            Act.FORGE -> if (pressed && power && p.reloadT <= 0f) {
                val g = p.gun
                if (!g.forged) { if (pay(FpsRules.FORGE_COST)) { p.guns[p.cur] = HeldGun(g.gun, forged = true); emit(FpsEvent.Type.BOUGHT, text = "Forged ${g.gun.name}") } }
                else if (g.reserve < g.reserveMax && pay(FpsRules.REFORGE_COST)) { g.refill(); emit(FpsEvent.Type.BOUGHT, text = "Ammo") }
            }
        }
    }

    private fun ammoCost(g: HeldGun) = if (g.forged) 2500 else g.gun.cost / 2

    private fun pay(cost: Int): Boolean {
        if (player.points < cost) { emit(FpsEvent.Type.DENIED); return false }
        player.points -= cost; return true
    }

    private fun giveGun(g: HeldGun) {
        val p = player
        if (p.guns.size < 2) { p.guns += g; p.cur = p.guns.size - 1 } else p.guns[p.cur] = g
        p.reloadT = 0f; p.swapT = 0.45f
        emit(FpsEvent.Type.BOUGHT, text = g.name)
    }

    private fun computePrompt() {
        val p = player
        promptOk = true
        prompt = if (p.downed) "" else when (act) {
            Act.NONE -> ""
            Act.WINDOW -> "Hold USE to rebuild the barrier"
            Act.DOOR -> "USE: open the door [${actDoor!!.cost}]".also { promptOk = p.points >= actDoor!!.cost }
            Act.WALL -> {
                val gun = actProp!!.gun!!; val owned = p.guns.firstOrNull { it.gun == gun }
                if (owned != null) "USE: ${gun.name} ammo [${ammoCost(owned)}]".also { promptOk = p.points >= ammoCost(owned) && owned.reserve < owned.reserveMax }
                else "USE: buy ${gun.name} [${gun.cost}]".also { promptOk = p.points >= gun.cost }
            }
            Act.BOX -> when (boxState) {
                BoxState.IDLE -> "USE: Mystery Box [${FpsRules.BOX_COST}]".also { promptOk = p.points >= FpsRules.BOX_COST }
                BoxState.ROLLING -> "...".also { promptOk = false }
                BoxState.READY -> "USE: take the ${boxGun!!.name}"
            }
            Act.PERK -> {
                val perk = actProp!!.perk!!
                when {
                    perk.needsPower && !power -> "${perk.title}: you need to turn on the power".also { promptOk = false }
                    perk in p.perks -> "${perk.title} (you have it)".also { promptOk = false }
                    perk == Perk.SECOND_WIND && p.secondWindBought >= FpsRules.SECOND_WIND_USES -> "${perk.title} is used up".also { promptOk = false }
                    else -> "USE: drink ${perk.title} [${perk.cost}]".also { promptOk = p.points >= perk.cost }
                }
            }
            Act.POWER -> if (power) "" else "USE: turn on the power"
            Act.FORGE -> when {
                !power -> "Forge: you need to turn on the power".also { promptOk = false }
                !p.gun.forged -> "USE: forge your ${p.gun.gun.name} [${FpsRules.FORGE_COST}]".also { promptOk = p.points >= FpsRules.FORGE_COST }
                else -> "USE: refill forged ammo [${FpsRules.REFORGE_COST}]".also { promptOk = p.points >= FpsRules.REFORGE_COST && p.gun.reserve < p.gun.reserveMax }
            }
        }
    }
}

private val DXS = intArrayOf(1, -1, 0, 0); private val DYS = intArrayOf(0, 0, 1, -1)

fun angleDiff(a: Float, b: Float): Float { var d = (b - a) % (2 * PI.toFloat()); if (d > PI) d -= 2 * PI.toFloat(); if (d < -PI) d += 2 * PI.toFloat(); return d }
