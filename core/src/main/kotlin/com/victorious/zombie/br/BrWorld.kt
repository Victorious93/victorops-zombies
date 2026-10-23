package com.victorious.zombie.br

import com.victorious.zombie.logic.Ability
import com.victorious.zombie.logic.Characters
import com.victorious.zombie.net.Msg
import com.victorious.zombie.sim.PlayerInput
import com.victorious.zombie.sim.Sim
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

enum class Phase { LOBBY, DEPLOY, LIVE, ENDED }
enum class LootKind { WEAPON, MEDKIT, CELL }

class Fighter(val id: Int, val name: String, val characterId: String, val bot: Boolean) {
    val character get() = Characters.byId(characterId)
    var x = 0f; var y = 0f; var kvx = 0f; var kvy = 0f
    var aim = 0f
    val maxHp: Float = 100f + (character.maxHealth - 100f) * 0.5f
    var hp = maxHp; var shield = 0f
    var weapon = BrWeapon.START; var rounds = weapon.mag; var reloadLeft = 0f; var fireCd = 0f
    var abilityCd = 0f; var useCd = 0f
    /** 0 = not healing, 1 = medkit, 2 = shield cell. */
    var healKind = 0; var healT = 0f
    var medkits = 0; var cells = 0
    var alive = true; var kills = 0; var placement = 0
    var protectedT = 0f; var reduceT = 0f
    var killedBy = ""; var killerId = -1
    var input = PlayerInput()
    var spectate = -1

    val reloading get() = reloadLeft > 0f
    val healDuration get() = if (healKind == 1) BrWorld.MEDKIT_TIME else BrWorld.CELL_TIME
}

class Zomb(val id: Int, var x: Float, var y: Float, var hp: Float)
class Bullet(var x: Float, var y: Float, val vx: Float, val vy: Float, val dmg: Float, var pierce: Int, val splash: Float, val owner: Int, val weaponName: String, var life: Float) {
    val hit = HashSet<Int>()
}
class Loot(val id: Int, val kind: LootKind, var x: Float, var y: Float, val weapon: BrWeapon? = null)
class Airdrop(val x: Float, val y: Float, var t: Float)
class HitFx(val seq: Int, val x: Float, val y: Float, val amount: Int, val src: Int, val dst: Int, val kill: Boolean, var age: Float = 0f)
private class FeedLine(val text: String, var age: Float = 0f)

class ZoneStep(val hold: Float, val shrink: Float, val endRadius: Float, val dps: Float)

/**
 * Blackout Royale: authoritative free-for-all simulation. No rendering, no devices, no sockets: the host feeds it
 * inputs and calls [step]; clients read [snapshot]s. Bots use exactly the same [PlayerInput] path as humans.
 *
 * [autoStartS] is how long the lobby waits for the host (USE) before starting by itself; 0 or less starts at once.
 */
class BrWorld(
    seed: Long = System.nanoTime(),
    private val autoStartS: Float = 1.5f,
    val botSkill: BotSkill = BotSkill.NORMAL,
    val field: Int = BrConst.FIELD,
    private val withBots: Boolean = true,
) : Sim {
    companion object {
        const val MAX_HUMANS = 4
        const val SPEED = 230f
        const val MAX_SHIELD = 100f
        const val CARRY = 3
        const val MEDKIT_TIME = 2.2f; const val CELL_TIME = 1.6f
        const val MEDKIT_HEAL = 50f; const val CELL_SHIELD = 50f
        const val DEPLOY_TIME = 5f
        const val AIRDROP_FALL = 12f
        const val START_RADIUS = 1700f
        const val ZOMBIE_CAP = 12
        const val ZOMBIE_SPEED = 85f; const val ZOMBIE_DPS = 14f; const val ZOMBIE_HP = 60f
        const val PICKUP_RANGE = 46f; const val AUTO_PICKUP = 26f
        const val BASS_RADIUS = 220f; const val BASS_KNOCK = 170f; const val BASS_DAMAGE = 20f
        const val FORTIFY_SHIELD = 35f; const val FORTIFY_TIME = 3f
        const val HOST_ID = 0
        const val BOT_ID_BASE = 100
        val ZONES = listOf(
            ZoneStep(40f, 40f, 1100f, 1.5f), ZoneStep(35f, 35f, 700f, 3f), ZoneStep(30f, 30f, 400f, 5f),
            ZoneStep(25f, 25f, 200f, 8f), ZoneStep(20f, 20f, 80f, 12f), ZoneStep(10f, 15f, 0f, 20f),
        )
        private val BOT_NAMES = listOf("Rook", "Vex", "Juno", "Kade", "Mox", "Nyx", "Pike", "Sable", "Tarn", "Wren", "Zed", "Ember", "Flint", "Gale", "Haze")
    }

    private val rng = Random(seed)
    var map = BrMap(rng.nextInt()); private set
    var phase = Phase.LOBBY; private set
    val fighters = LinkedHashMap<Int, Fighter>()
    val bullets = ArrayList<Bullet>(); val zombies = ArrayList<Zomb>(); val loot = ArrayList<Loot>(); val airdrops = ArrayList<Airdrop>()
    private val hitFx = ArrayList<HitFx>(); private val feed = ArrayList<FeedLine>()
    private val brains = HashMap<Int, BrBrain>()
    private var nextId = 1; private var hitSeq = 1
    var banner = ""; private set
    private var bannerT = 0f
    var winnerId = -1; private set
    var matchTime = 0f; private set
    private var phaseT = autoStartS

    // Dead Zone
    var zoneCx = BrConst.CENTER; private set
    var zoneCy = BrConst.CENTER; private set
    var zoneR = START_RADIUS; private set
    var nextCx = BrConst.CENTER; private set
    var nextCy = BrConst.CENTER; private set
    var nextR = ZONES[0].endRadius; private set
    var zoneIdx = 0; private set
    var zoneShrinking = false; private set
    var zoneT = 0f; private set
    private var fromCx = 0f; private var fromCy = 0f; private var fromR = 0f
    private var zombieCd = 0f

    /** Seconds until the zone changes state (hold -> shrink -> next hold). */
    val zoneTimeLeft: Float get() = if (zoneIdx >= ZONES.size) 0f else (if (zoneShrinking) ZONES[zoneIdx].shrink else ZONES[zoneIdx].hold) - zoneT
    val zoneDps: Float get() = ZONES[min(zoneIdx, ZONES.size - 1)].dps
    val lobbyTimeLeft: Float get() = max(0f, phaseT)
    val deployTimeLeft: Float get() = max(0f, phaseT)

    // ---- Sim ----------------------------------------------------------------------------------------------------
    override val stateType: String get() = Msg.ROYALE_STATE
    override val kind: String? get() = "royale"
    override fun hasPlayer(id: Int) = fighters[id]?.bot == false

    override fun join(id: Int, characterId: String): Boolean {
        if (phase != Phase.LOBBY || humans().size >= MAX_HUMANS || fighters[id] != null || id >= BOT_ID_BASE) return false
        val c = Characters.byId(characterId)
        fighters[id] = Fighter(id, c.name.substringBefore(' '), c.id, bot = false)
        return true
    }

    override fun leave(id: Int) {
        val f = fighters[id] ?: return
        if (f.bot) return
        if (phase == Phase.LIVE && f.alive) eliminate(f, -1, "", "${f.name} left the game")
        fighters.remove(id)
    }

    override fun applyInput(id: Int, input: PlayerInput) { fighters[id]?.takeIf { !it.bot }?.input = input }
    override fun step(dt: Float) = update(dt)
    override fun stateText(forId: Int): String = BrCodec.toText(snapshot(forId))

    /** Bot decision summary for tests and tuning; empty for humans. */
    fun brainDebug(id: Int): String = brains[id]?.debug() ?: ""

    fun humans() = fighters.values.filter { !it.bot }
    fun aliveCount() = fighters.values.count { it.alive }

    // ---- Lifecycle ----------------------------------------------------------------------------------------------
    /** Starts the match now: fills the field with bots, builds a new map and drops everyone. */
    fun startMatch() {
        check(phase == Phase.LOBBY) { "match already started" }
        map = BrMap(rng.nextInt())
        brains.clear()
        if (withBots) {
            val chars = Characters.ALL
            var i = 0
            while (fighters.size < field) {
                val id = BOT_ID_BASE + i
                fighters[id] = Fighter(id, BOT_NAMES[i % BOT_NAMES.size], chars[rng.nextInt(chars.size)].id, bot = true)
                brains[id] = BrBrain(botSkill, rng.nextInt()); i++
            }
        }
        val spots = map.spawnPoints.shuffled(rng)
        fighters.values.forEachIndexed { i, f ->
            val p = spots[i % spots.size]
            f.x = p.x; f.y = p.y; f.aim = atan2(BrConst.CENTER - p.y, BrConst.CENTER - p.x)
            f.protectedT = DEPLOY_TIME + 3f
        }
        placeLoot()
        zoneCx = BrConst.CENTER; zoneCy = BrConst.CENTER; zoneR = START_RADIUS; zoneIdx = 0; zoneShrinking = false; zoneT = 0f
        beginHold()
        zombieCd = 4f; matchTime = 0f; winnerId = -1
        phase = Phase.DEPLOY; phaseT = DEPLOY_TIME
        say("Drop in", 3f)
    }

    /** Back to the lobby with the same humans (rematch). */
    fun resetToLobby(waitS: Float = 6f) {
        fighters.values.removeAll { it.bot }
        for (f in fighters.values.toList()) fighters[f.id] = Fighter(f.id, f.name, f.characterId, false)
        brains.clear(); bullets.clear(); zombies.clear(); loot.clear(); airdrops.clear(); hitFx.clear(); feed.clear()
        phase = Phase.LOBBY; phaseT = waitS; winnerId = -1; banner = ""; matchTime = 0f
    }

    private fun say(text: String, secs: Float) { banner = text; bannerT = secs }
    private fun announce(text: String) { feed += FeedLine(text); while (feed.size > 6) feed.removeAt(0) }

    // ---- Update -------------------------------------------------------------------------------------------------
    fun update(dt: Float) {
        bannerT -= dt; if (bannerT <= 0f && phase != Phase.ENDED) banner = ""
        for (h in hitFx) h.age += dt; hitFx.removeAll { it.age > 0.7f }
        for (l in feed) l.age += dt; feed.removeAll { it.age > 8f }
        when (phase) {
            Phase.LOBBY -> {
                phaseT -= dt
                val hostGo = fighters[HOST_ID]?.input?.use == true
                if (phaseT <= 0f || (hostGo && humans().isNotEmpty() && autoStartS > 0f)) startMatch()
            }
            Phase.DEPLOY -> {
                phaseT -= dt
                if (phaseT <= 0f) { phase = Phase.LIVE; say("GO! Stay inside the zone", 2.5f) }
                else say("Dropping in ${kotlin.math.ceil(phaseT).toInt()}", 1f)
            }
            Phase.LIVE -> live(dt)
            Phase.ENDED -> if (humans().isNotEmpty() && (fighters[HOST_ID]?.input?.use == true) && phaseT <= 0f) resetToLobby() else phaseT -= dt
        }
    }

    private fun live(dt: Float) {
        matchTime += dt
        updateZone(dt)
        for (f in fighters.values) {
            if (!f.alive) continue
            if (f.bot) f.input = brains.getValue(f.id).think(this, f, dt)
            tickFighter(f, dt)
        }
        separate()
        updateBullets(dt)
        updateZombies(dt)
        zoneDamage(dt)
        updateAirdrops(dt)
        spawnZombies(dt)
        pickupLoot()
        for (f in fighters.values) if (f.protectedT > 0f) f.protectedT -= dt
        checkEnd()
    }

    // ---- Zone ---------------------------------------------------------------------------------------------------
    private fun beginHold() {
        val step = ZONES[zoneIdx]
        fromCx = zoneCx; fromCy = zoneCy; fromR = zoneR
        nextR = step.endRadius
        val maxD = max(0f, zoneR - nextR)
        val a = rng.nextFloat() * 2 * PI.toFloat(); val d = maxD * (0.25f + 0.55f * rng.nextFloat())
        var nx = (zoneCx + cos(a) * d).coerceIn(200f, BrConst.SIZE - 200f); var ny = (zoneCy + sin(a) * d).coerceIn(200f, BrConst.SIZE - 200f)
        val off = hypot(nx - zoneCx, ny - zoneCy)
        if (off > maxD && off > 0f) { nx = zoneCx + (nx - zoneCx) * maxD / off; ny = zoneCy + (ny - zoneCy) * maxD / off }
        nextCx = nx; nextCy = ny
        zoneShrinking = false; zoneT = 0f
        if (zoneIdx in 1..3) dropSupply()
    }

    private fun updateZone(dt: Float) {
        if (zoneIdx >= ZONES.size) return
        val step = ZONES[zoneIdx]
        zoneT += dt
        if (!zoneShrinking) {
            if (zoneT >= step.hold) { zoneShrinking = true; zoneT = 0f; say("The Dead Zone is closing!", 2.5f) }
        } else {
            val f = (zoneT / step.shrink).coerceIn(0f, 1f)
            zoneCx = fromCx + (nextCx - fromCx) * f; zoneCy = fromCy + (nextCy - fromCy) * f; zoneR = fromR + (nextR - fromR) * f
            if (zoneT >= step.shrink) {
                zoneCx = nextCx; zoneCy = nextCy; zoneR = nextR
                zoneIdx++
                if (zoneIdx < ZONES.size) beginHold() else { zoneIdx = ZONES.size; zoneShrinking = false }
            }
        }
    }

    fun inZone(x: Float, y: Float) = hypot(x - zoneCx, y - zoneCy) <= zoneR

    private fun zoneDamage(dt: Float) {
        val dps = zoneDps
        for (f in fighters.values) if (f.alive && f.protectedT <= 0f && !inZone(f.x, f.y)) damage(f, dps * dt, -1, "the Dead Zone", ignoreShield = true, interrupt = false, fx = false)
    }

    // ---- Fighters -----------------------------------------------------------------------------------------------
    private fun tickFighter(f: Fighter, dt: Float) {
        val inp = f.input
        f.abilityCd -= dt; f.useCd -= dt; f.fireCd -= dt; if (f.reduceT > 0f) f.reduceT -= dt
        // aim
        val al = hypot(inp.aimX, inp.aimY)
        if (al > 0.2f) f.aim = atan2(inp.aimY, inp.aimX)
        // reload
        if (f.reloading) { f.reloadLeft -= dt; if (f.reloadLeft <= 0f) { f.reloadLeft = 0f; f.rounds = f.weapon.mag } }
        else if (inp.reload && f.rounds < f.weapon.mag) f.reloadLeft = f.weapon.reload
        // heal channel
        if (f.healKind != 0) {
            if (!inp.heal || inp.fire) cancelHeal(f)
            else { f.healT += dt; if (f.healT >= f.healDuration) finishHeal(f) }
        } else if (inp.heal && !inp.fire) {
            val k = chooseHeal(f)
            if (k != 0) { f.healKind = k; f.healT = 0f }
        }
        // movement
        var dx = inp.dx; var dy = inp.dy
        val len = hypot(dx, dy); if (len > 1f) { dx /= len; dy /= len }
        val speed = SPEED * f.character.speedMult * (if (f.healKind != 0) 0.55f else 1f)
        f.kvx -= f.kvx * min(1f, 9f * dt); f.kvy -= f.kvy * min(1f, 9f * dt)
        val out = tmp
        map.resolve(f.x + (dx * speed + f.kvx) * dt, f.y + (dy * speed + f.kvy) * dt, BrConst.BODY_R, out)
        f.x = out[0]; f.y = out[1]
        // actions
        if (inp.ability && f.abilityCd <= 0f) useAbility(f)
        if (inp.use && f.useCd <= 0f) { f.useCd = 0.35f; swapWeapon(f) }
        if (inp.fire && al > 0.2f && f.fireCd <= 0f && !f.reloading && f.healKind == 0) {
            if (f.rounds <= 0) f.reloadLeft = f.weapon.reload else shoot(f)
        }
    }
    private val tmp = FloatArray(2)

    private fun chooseHeal(f: Fighter): Int {
        val needHp = f.maxHp - f.hp; val needSh = MAX_SHIELD - f.shield
        if (f.medkits > 0 && needHp >= 25f) return 1
        if (f.cells > 0 && needSh >= 25f) return 2
        if (f.medkits > 0 && needHp > 5f) return 1
        if (f.cells > 0 && needSh > 5f) return 2
        return 0
    }

    private fun cancelHeal(f: Fighter) { f.healKind = 0; f.healT = 0f }

    private fun finishHeal(f: Fighter) {
        if (f.healKind == 1) { f.medkits--; f.hp = min(f.maxHp, f.hp + MEDKIT_HEAL) }
        else { f.cells--; f.shield = min(MAX_SHIELD, f.shield + CELL_SHIELD) }
        cancelHeal(f)
    }

    private fun shoot(f: Fighter) {
        val w = f.weapon; val g = w.gun
        repeat(g.pellets) {
            val a = f.aim + (rng.nextFloat() - 0.5f) * 2f * g.spreadDeg * (PI.toFloat() / 180f)
            bullets += Bullet(f.x, f.y, cos(a) * g.bulletSpeed, sin(a) * g.bulletSpeed, w.damage, g.pierce, g.splash, f.id, w.name, g.range / g.bulletSpeed)
        }
        f.fireCd = w.interval; f.rounds--
        if (f.rounds <= 0) f.reloadLeft = w.reload
    }

    private fun swapWeapon(f: Fighter) {
        val l = loot.filter { it.kind == LootKind.WEAPON && hypot(it.x - f.x, it.y - f.y) < PICKUP_RANGE }.minByOrNull { hypot(it.x - f.x, it.y - f.y) } ?: return
        dropWeapon(f)
        f.weapon = l.weapon!!; f.rounds = f.weapon.mag; f.reloadLeft = 0f; f.fireCd = 0.25f
        loot.remove(l)
    }

    private fun dropWeapon(f: Fighter) {
        if (f.weapon.gun == BrGuns.SIDEARM && f.weapon.rarity == Rarity.COMMON) return
        loot += Loot(nextId++, LootKind.WEAPON, f.x + 10f, f.y + 10f, f.weapon)
    }

    private fun useAbility(f: Fighter) {
        when (f.character.ability) {
            Ability.BASS_DROP -> {
                for (o in fighters.values) {
                    if (o === f || !o.alive) continue
                    val d = hypot(o.x - f.x, o.y - f.y); if (d > BASS_RADIUS) continue
                    if (d > 0.01f) { o.kvx += (o.x - f.x) / d * BASS_KNOCK * 9f; o.kvy += (o.y - f.y) / d * BASS_KNOCK * 9f }
                    damage(o, BASS_DAMAGE, f.id, "Bass Drop")
                }
                for (z in zombies.toList()) {
                    val d = hypot(z.x - f.x, z.y - f.y); if (d > BASS_RADIUS) continue
                    if (d > 0.01f) { z.x += (z.x - f.x) / d * BASS_KNOCK * 0.5f; z.y += (z.y - f.y) / d * BASS_KNOCK * 0.5f }
                    hurtZombie(z, 40f, f.id)
                }
            }
            Ability.FORTIFY -> { f.shield = min(MAX_SHIELD, f.shield + FORTIFY_SHIELD); f.reduceT = FORTIFY_TIME }
        }
        cancelHeal(f)
        f.abilityCd = if (f.character.ability == Ability.BASS_DROP) 30f else 35f
    }

    private fun separate() {
        val list = fighters.values.filter { it.alive }
        for (i in list.indices) for (j in i + 1 until list.size) {
            val a = list[i]; val b = list[j]
            val dx = b.x - a.x; val dy = b.y - a.y; val d = hypot(dx, dy); val min = BrConst.BODY_R * 2f
            if (d >= min) continue
            val nx = if (d > 0.01f) dx / d else 1f; val ny = if (d > 0.01f) dy / d else 0f
            val push = (min - d) / 2f
            map.resolve(a.x - nx * push, a.y - ny * push, BrConst.BODY_R, tmp); a.x = tmp[0]; a.y = tmp[1]
            map.resolve(b.x + nx * push, b.y + ny * push, BrConst.BODY_R, tmp); b.x = tmp[0]; b.y = tmp[1]
        }
    }

    // ---- Damage -------------------------------------------------------------------------------------------------
    /** Applies damage. Source id < 0 is the environment ([-1] zone, [-2] horde). Returns true if it killed. */
    fun damage(t: Fighter, amount: Float, src: Int, srcName: String, ignoreShield: Boolean = false, interrupt: Boolean = true, fx: Boolean = true): Boolean {
        if (!t.alive || t.protectedT > 0f || amount <= 0f || phase != Phase.LIVE) return false
        var a = amount * (if (t.reduceT > 0f) 0.5f else 1f)
        val dealt = a
        if (!ignoreShield && t.shield > 0f) { val s = min(t.shield, a); t.shield -= s; a -= s }
        t.hp -= a
        if (interrupt && t.healKind != 0) cancelHeal(t)
        t.killerId = src; t.killedBy = srcName
        val dead = t.hp <= 0f
        if (fx && dealt >= 1f) hitFx += HitFx(hitSeq++, t.x, t.y, dealt.toInt(), src, t.id, dead)
        if (dead) eliminate(t, src, srcName, null)
        return dead
    }

    private fun eliminate(t: Fighter, src: Int, srcName: String, text: String?) {
        if (!t.alive) return
        t.placement = aliveCount()
        t.alive = false; t.hp = 0f; cancelHeal(t)
        val killer = fighters[src]
        if (killer != null && killer !== t) killer.kills++
        dropWeapon(t)
        loot += Loot(nextId++, LootKind.CELL, t.x - 10f, t.y, null)
        announce(text ?: when {
            killer != null && killer !== t -> "${killer.name} eliminated ${t.name} (${srcName})"
            src == -1 -> "${t.name} was claimed by the Dead Zone"
            src == -2 -> "${t.name} was eaten by the horde"
            else -> "${t.name} is out"
        })
    }

    // ---- Bullets ------------------------------------------------------------------------------------------------
    private class Cand(val t: Float, val f: Fighter?, val z: Zomb?)
    private val cands = ArrayList<Cand>()

    private fun updateBullets(dt: Float) {
        val it = bullets.iterator()
        while (it.hasNext()) {
            val b = it.next()
            val x0 = b.x; val y0 = b.y; val x1 = x0 + b.vx * dt; val y1 = y0 + b.vy * dt
            b.life -= dt
            val wallT = map.firstWallT(x0, y0, x1, y1)
            val tWall = if (wallT < 0f) 2f else wallT
            cands.clear()
            for (f in fighters.values) {
                if (!f.alive || f.id == b.owner || f.id in b.hit) continue
                val t = Geo.segCircleT(x0, y0, x1, y1, f.x, f.y, BrConst.BODY_R + 2f); if (t >= 0f && t < tWall) cands += Cand(t, f, null)
            }
            for (z in zombies) {
                if ((z.id + 10_000) in b.hit) continue
                val t = Geo.segCircleT(x0, y0, x1, y1, z.x, z.y, BrConst.ZOMBIE_R + 2f); if (t >= 0f && t < tWall) cands += Cand(t, null, z)
            }
            cands.sortBy { c -> c.t }
            var ended = false
            for (c in cands) {
                val hx = x0 + (x1 - x0) * c.t; val hy = y0 + (y1 - y0) * c.t
                if (c.f != null) { b.hit += c.f.id; damage(c.f, b.dmg, b.owner, b.weaponName) } else { b.hit += c.z!!.id + 10_000; hurtZombie(c.z, b.dmg, b.owner) }
                if (b.splash > 0f) { explode(hx, hy, b); ended = true; break }
                if (b.pierce > 0) b.pierce-- else { ended = true; break }
            }
            if (!ended && tWall <= 1f) {
                if (b.splash > 0f) explode(x0 + (x1 - x0) * tWall, y0 + (y1 - y0) * tWall, b)
                ended = true
            }
            if (ended) { it.remove(); continue }
            b.x = x1; b.y = y1
            if (b.life <= 0f) { if (b.splash > 0f) explode(b.x, b.y, b); it.remove() }
        }
    }

    private fun explode(x: Float, y: Float, b: Bullet) {
        val base = b.dmg * 0.6f
        for (f in fighters.values) {
            if (!f.alive || f.id == b.owner || f.id in b.hit) continue
            val d = hypot(f.x - x, f.y - y); if (d > b.splash) continue
            damage(f, base * (1f - 0.6f * d / b.splash), b.owner, b.weaponName)
        }
        for (z in zombies.toList()) {
            if ((z.id + 10_000) in b.hit) continue
            val d = hypot(z.x - x, z.y - y); if (d > b.splash) continue
            hurtZombie(z, base * (1f - 0.6f * d / b.splash), b.owner)
        }
    }

    // ---- Horde --------------------------------------------------------------------------------------------------
    private fun hurtZombie(z: Zomb, dmg: Float, src: Int) {
        z.hp -= dmg
        fighters[src]?.takeIf { dmg >= 1f }?.let { hitFx += HitFx(hitSeq++, z.x, z.y, dmg.toInt(), src, -z.id - 1, z.hp <= 0f) }
        if (z.hp <= 0f) {
            zombies.remove(z)
            if (rng.nextFloat() < 0.2f) loot += Loot(nextId++, if (rng.nextBoolean()) LootKind.MEDKIT else LootKind.CELL, z.x, z.y, null)
        }
    }

    private fun spawnZombies(dt: Float) {
        if (zoneIdx < 1 || zombies.size >= ZOMBIE_CAP) return
        zombieCd -= dt
        if (zombieCd > 0f) return
        zombieCd = 2.5f
        repeat(8) {
            val a = rng.nextFloat() * 2 * PI.toFloat(); val d = zoneR + 50f + rng.nextFloat() * 150f
            val x = zoneCx + cos(a) * d; val y = zoneCy + sin(a) * d
            if (map.isFree(x, y, BrConst.ZOMBIE_R + 4f) && fighters.values.none { it.alive && hypot(it.x - x, it.y - y) < 300f }) {
                zombies += Zomb(nextId++, x, y, ZOMBIE_HP); return
            }
        }
    }

    private fun updateZombies(dt: Float) {
        val living = fighters.values.filter { it.alive }
        for (z in zombies) {
            val target = living.minByOrNull { hypot(it.x - z.x, it.y - z.y) }
            val tx: Float; val ty: Float
            if (target != null && hypot(target.x - z.x, target.y - z.y) < 650f) { tx = target.x; ty = target.y } else { tx = zoneCx; ty = zoneCy }
            val d = hypot(tx - z.x, ty - z.y)
            if (d > 1f) {
                map.resolve(z.x + (tx - z.x) / d * ZOMBIE_SPEED * dt, z.y + (ty - z.y) / d * ZOMBIE_SPEED * dt, BrConst.ZOMBIE_R, tmp)
                z.x = tmp[0]; z.y = tmp[1]
            }
            if (target != null && hypot(target.x - z.x, target.y - z.y) < BrConst.BODY_R + BrConst.ZOMBIE_R + 6f)
                damage(target, ZOMBIE_DPS * dt, -2, "the horde", fx = false)
        }
    }

    // ---- Loot and airdrops --------------------------------------------------------------------------------------
    private fun placeLoot() {
        loot.clear(); airdrops.clear(); zombies.clear(); bullets.clear()
        for (s in map.lootSpots) {
            if (s.tier == 0) {
                val r = rng.nextInt(100)
                when { r < 50 -> addLoot(s.x, s.y, LootKind.WEAPON, BrLoot.rollWeapon(0, rng)); r < 75 -> addLoot(s.x, s.y, LootKind.MEDKIT, null); else -> addLoot(s.x, s.y, LootKind.CELL, null) }
            } else {
                addLoot(s.x - 8f, s.y, LootKind.WEAPON, BrLoot.rollWeapon(s.tier, rng))
                addLoot(s.x + 8f, s.y, if (rng.nextBoolean()) LootKind.MEDKIT else LootKind.CELL, null)
            }
        }
    }

    private fun addLoot(x: Float, y: Float, kind: LootKind, w: BrWeapon?) { loot += Loot(nextId++, kind, x, y, w) }

    private fun dropSupply() {
        val a = rng.nextFloat() * 2 * PI.toFloat(); val d = nextR * 0.6f * rng.nextFloat()
        val p = map.nearestFree(nextCx + cos(a) * d, nextCy + sin(a) * d, 40f)
        airdrops += Airdrop(p.x, p.y, AIRDROP_FALL)
        announce("Supply drop incoming!")
    }

    private fun updateAirdrops(dt: Float) {
        val it = airdrops.iterator()
        while (it.hasNext()) {
            val a = it.next(); a.t -= dt
            if (a.t > 0f) continue
            addLoot(a.x, a.y - 18f, LootKind.WEAPON, BrLoot.epicWeapon(rng))
            addLoot(a.x - 24f, a.y + 14f, LootKind.MEDKIT, null); addLoot(a.x + 24f, a.y + 14f, LootKind.MEDKIT, null)
            addLoot(a.x - 12f, a.y + 30f, LootKind.CELL, null); addLoot(a.x + 12f, a.y + 30f, LootKind.CELL, null)
            announce("Supply drop landed")
            it.remove()
        }
    }

    private fun pickupLoot() {
        val it = loot.iterator()
        while (it.hasNext()) {
            val l = it.next()
            if (l.kind == LootKind.WEAPON) continue
            val f = fighters.values.firstOrNull { o -> o.alive && hypot(o.x - l.x, o.y - l.y) < AUTO_PICKUP && (if (l.kind == LootKind.MEDKIT) o.medkits < CARRY else o.cells < CARRY) } ?: continue
            if (l.kind == LootKind.MEDKIT) f.medkits++ else f.cells++
            it.remove()
        }
    }

    // ---- End of match -------------------------------------------------------------------------------------------
    private fun checkEnd() {
        val alive = fighters.values.filter { it.alive }
        val humansLeft = alive.any { !it.bot }
        val hadHumans = fighters.values.any { !it.bot }
        if (alive.size > 1 && (humansLeft || !hadHumans)) return
        phase = Phase.ENDED; phaseT = 3f
        val winner = alive.singleOrNull()
        winnerId = winner?.id ?: -1
        winner?.placement = 1
        say(if (winner != null) "${winner.name} is the last one standing!" else "Nobody survived the Blackout", 999f)
    }

    // ---- Snapshot -----------------------------------------------------------------------------------------------
    fun snapshot(viewerId: Int): BrSnapshot {
        val me = fighters[viewerId]
        var focus = me
        if (me != null && !me.alive && phase == Phase.LIVE) {
            focus = fighters[me.spectate]?.takeIf { it.alive } ?: fighters[me.killerId]?.takeIf { it.alive } ?: fighters.values.firstOrNull { it.alive && !it.bot } ?: fighters.values.firstOrNull { it.alive }
            me.spectate = focus?.id ?: -1
        }
        val camX = focus?.x ?: me?.x ?: BrConst.CENTER; val camY = focus?.y ?: me?.y ?: BrConst.CENTER
        fun near(x: Float, y: Float) = hypot(x - camX, y - camY) <= BrConst.VIEW_RANGE
        val fs = fighters.values.filter { phase == Phase.LOBBY || it.id == viewerId || it === focus || (it.alive && near(it.x, it.y)) }
            .map { f -> BrFighterSnap(f.id, f.name, f.characterId, f.x, f.y, f.aim, f.hp, f.maxHp, f.shield, BrGuns.index(f.weapon.gun), f.weapon.rarity.ordinal, f.rounds, f.reloading, f.healKind != 0, f.alive, f.protectedT > 0f, f.reduceT > 0f) }
        val lobbyNames = if (phase == Phase.LOBBY) humans().map { it.name } else emptyList()
        val self = if (me == null) null else BrSelf(
            me.alive, me.kills, me.placement, me.medkits, me.cells, max(0f, me.abilityCd), if (me.healKind != 0) me.healT / me.healDuration else 0f,
            prompt(me), if (!me.alive) (focus?.name ?: "") else "", me.weapon.mag, max(0f, me.reloadLeft / max(0.01f, me.weapon.reload)),
        )
        val hits = hitFx.filter { it.src == viewerId || it.dst == viewerId }.map { BrHitSnap(it.seq, it.x, it.y, it.amount, it.src == viewerId, it.dst == viewerId, it.kill) }
        return BrSnapshot(
            map.seed, phase.ordinal, when (phase) { Phase.LOBBY -> phaseT; Phase.DEPLOY -> phaseT; else -> 0f }, aliveCount(), fighters.size,
            camX, camY, viewerId, focus?.id ?: -1,
            BrZoneSnap(zoneCx, zoneCy, zoneR, nextCx, nextCy, nextR, zoneTimeLeft, zoneShrinking, zoneDps, zoneIdx),
            self, fs,
            zombies.filter { near(it.x, it.y) }.map { BrZombieSnap(it.id, it.x, it.y) },
            bullets.filter { near(it.x, it.y) }.map { BrBulletSnap(it.x, it.y, atan2(it.vy, it.vx)) },
            loot.filter { near(it.x, it.y) }.map { BrLootSnap(it.id, it.kind.ordinal, it.x, it.y, it.weapon?.let { w -> BrGuns.index(w.gun) } ?: 0, it.weapon?.rarity?.ordinal ?: 0) },
            airdrops.map { BrAirdropSnap(it.x, it.y, it.t) }, hits, feed.map { it.text }.takeLast(5),
            if (bannerT > 0f || phase == Phase.ENDED) banner else "", fighters[winnerId]?.name ?: "", lobbyNames,
        )
    }

    private fun prompt(f: Fighter): String {
        if (!f.alive) return ""
        val l = loot.filter { it.kind == LootKind.WEAPON && hypot(it.x - f.x, it.y - f.y) < PICKUP_RANGE }.minByOrNull { hypot(it.x - f.x, it.y - f.y) } ?: return ""
        return "USE: swap to ${l.weapon!!.displayName}"
    }
}
