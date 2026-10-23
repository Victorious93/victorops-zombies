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
    val maxHp: Float = BrWorld.BASE_HP + (character.maxHealth - 100f) * 0.5f
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

    // squads: -1 until the match starts
    var squad = -1
    /** Down but not out: crawls, cannot act, bleeds out in [downedT] seconds unless a teammate revives them. Still [alive]. */
    var downed = false; var downedT = 0f
    /** Revive progress 0..1 on a downed fighter. */
    var reviveP = 0f
    /** Id of the downed teammate this fighter is reviving this tick, or -1. [reviveBreakT] > 0: damage broke the channel. */
    var reviveTarget = -1; var reviveBreakT = 0f; var revives = 0
    /** A mate is working on this downed fighter right now (they hold still so the reviver does not have to chase them). */
    var beingRevived = false

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
    squadSize: Int = 1,
) : Sim {
    companion object {
        const val MAX_HUMANS = 4
        const val SPEED = 230f
        const val BASE_HP = 160f
        const val MAX_SHIELD = 100f
        const val CARRY = 3
        const val MEDKIT_TIME = 2.2f; const val CELL_TIME = 1.6f
        const val MEDKIT_HEAL = 50f; const val CELL_SHIELD = 50f
        const val DEPLOY_TIME = 5f
        const val AIRDROP_FALL = 12f
        const val START_RADIUS = 2270f // reaches the corners of the 3200 map
        const val ZOMBIE_CAP = 12
        const val ZOMBIE_SPEED = 85f; const val ZOMBIE_DPS = 14f; const val ZOMBIE_HP = 60f
        const val PICKUP_RANGE = 46f; const val AUTO_PICKUP = 26f
        const val BASS_RADIUS = 220f; const val BASS_KNOCK = 170f; const val BASS_DAMAGE = 20f
        const val FORTIFY_SHIELD = 35f; const val FORTIFY_TIME = 3f
        const val HOST_ID = 0
        const val MAX_SQUAD = 4
        const val BLEED_TIME = 30f
        const val CRAWL_SPEED = 0.25f
        const val REVIVE_TIME = 4f; const val REVIVE_RANGE = 60f; const val REVIVE_HP = 0.4f
        const val REVIVE_SLOW = 0.5f; const val REVIVE_DECAY = 0.5f; const val REVIVE_BREAK = 0.8f
        /** Seconds of bleed-out an enemy hit or zone/horde damage costs per point of damage. */
        const val BLEED_PER_DMG = 0.25f
        const val BOT_ID_BASE = 100
        val ZONES = listOf(
            ZoneStep(40f, 40f, 1450f, 1.5f), ZoneStep(35f, 35f, 920f, 3f), ZoneStep(30f, 30f, 540f, 5f),
            ZoneStep(25f, 25f, 260f, 8f), ZoneStep(20f, 20f, 100f, 12f), ZoneStep(10f, 15f, 0f, 20f),
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
    var winnerSquad = -1; private set

    /** Fighters per squad: 1 = free-for-all (the original mode), 2..4 = squads with downed state and revives. Host sets it in the lobby. */
    var squadSize = squadSize.coerceIn(1, MAX_SQUAD); private set
    fun setSquadSize(n: Int) { if (phase == Phase.LOBBY) squadSize = n.coerceIn(1, MAX_SQUAD) }
    /** Number of squads in the match (valid once it started). */
    var squadCount = 0; private set

    // measurements for tests and tuning
    var statDowns = 0; private set
    var statRevivesStarted = 0; private set
    var statRevivesInterrupted = 0; private set
    var statRevives = 0; private set
    var statBleedOuts = 0; private set
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
        assignSquads()
        val spots = map.spawnPoints.shuffled(rng)
        if (squadSize <= 1) {
            fighters.values.forEachIndexed { i, f ->
                val p = spots[i % spots.size]
                f.x = p.x; f.y = p.y; f.aim = atan2(BrConst.CENTER - p.y, BrConst.CENTER - p.x)
            }
        } else landSquads(spots)
        for (f in fighters.values) f.protectedT = DEPLOY_TIME + 3f
        statDowns = 0; statRevivesStarted = 0; statRevivesInterrupted = 0; statRevives = 0; statBleedOuts = 0; winnerSquad = -1
        placeLoot()
        assignLandingAreas()
        zoneCx = BrConst.CENTER; zoneCy = BrConst.CENTER; zoneR = START_RADIUS; zoneIdx = 0; zoneShrinking = false; zoneT = 0f
        beginHold()
        zombieCd = 4f; matchTime = 0f; winnerId = -1
        phase = Phase.DEPLOY; phaseT = DEPLOY_TIME
        say("Drop in", 3f)
    }

    /**
     * Humans fill squads in join order (squad 0 first, spilling into the next), bots fill the gaps. With [squadSize] 1
     * every fighter is its own squad, so the free-for-all is just the special case.
     */
    private fun assignSquads() {
        val size = squadSize
        val counts = IntArray(fighters.size + 1)
        for ((i, h) in humans().withIndex()) { h.squad = i / size; counts[h.squad]++ }
        for (f in fighters.values) {
            if (!f.bot) continue
            var s = 0
            while (counts[s] >= size) s++
            f.squad = s; counts[s]++
        }
        squadCount = (fighters.values.maxOfOrNull { it.squad } ?: -1) + 1
    }

    /** Squads land together at one anchor, different squads as far apart as the spawn ring allows. */
    private fun landSquads(spots: List<Pt>) {
        val anchors = ArrayList<Pt>()
        anchors += spots[0]
        while (anchors.size < squadCount) {
            val next = spots.filter { c -> anchors.none { it === c } }.maxByOrNull { c -> anchors.minOf { hypot(it.x - c.x, it.y - c.y) } } ?: spots[anchors.size % spots.size]
            anchors += next
        }
        for (sq in 0 until squadCount) {
            val a = anchors[sq]
            val base = rng.nextFloat() * 2 * PI.toFloat()
            fighters.values.filter { it.squad == sq }.forEachIndexed { k, f ->
                val ang = base + k * 2 * PI.toFloat() / MAX_SQUAD
                val p = if (k == 0) a else map.nearestFree(a.x + cos(ang) * 70f, a.y + sin(ang) * 70f, BrConst.BODY_R + 4f)
                f.x = p.x; f.y = p.y; f.aim = atan2(BrConst.CENTER - p.y, BrConst.CENTER - p.x)
            }
        }
    }

    /**
     * Gives every bot its own area to loot first, spread out so neighbours do not all pick the same building. Humans
     * claim the spot nearest their landing so bots keep clear of them too.
     */
    private fun assignLandingAreas() {
        val taken = ArrayList<Pt>()
        for (h in fighters.values.filter { !it.bot }) map.lootSpots.minByOrNull { hypot(it.x - h.x, it.y - h.y) }?.let { taken += Pt(it.x, it.y) }
        if (squadSize > 1) { assignSquadAreas(taken); return }
        for (f in fighters.values.filter { it.bot }.shuffled(rng)) {
            val brain = brains[f.id] ?: continue
            val near = map.lootSpots.sortedBy { hypot(it.x - f.x, it.y - f.y) }.take(16)
            val ordered = if (brain.aggression > 0.65f) near.sortedBy { if (it.tier > 0) 0 else 1 } else near.sortedBy { if (it.tier > 0) 1 else 0 }
            var pick: LootSpot? = null
            for (sep in listOf(700f, 520f, 360f, 0f)) {
                pick = ordered.firstOrNull { c -> taken.none { hypot(it.x - c.x, it.y - c.y) < sep } }
                if (pick != null) break
            }
            val p = pick ?: near.first()
            taken += Pt(p.x, p.y); brain.setHome(p.x, p.y)
        }
    }

    /**
     * One area per squad (a squad with a human uses the spot nearest that human), and each member gets one of the three
     * nearest loot spots, so a squad loots one neighbourhood together instead of three corners of the map.
     */
    private fun assignSquadAreas(taken: ArrayList<Pt>) {
        for (sq in (0 until squadCount).shuffled(rng)) {
            val members = fighters.values.filter { it.squad == sq }
            val bots = members.filter { it.bot }
            if (bots.isEmpty()) continue
            val human = members.firstOrNull { !it.bot }
            val lead = human ?: members.first()
            val aggression = bots.mapNotNull { brains[it.id]?.aggression }.average().toFloat()
            val near = map.lootSpots.sortedBy { hypot(it.x - lead.x, it.y - lead.y) }.take(16)
            val ordered = if (aggression > 0.65f) near.sortedBy { if (it.tier > 0) 0 else 1 } else near.sortedBy { if (it.tier > 0) 1 else 0 }
            var pick: LootSpot? = null
            if (human != null) pick = near.first()
            else for (sep in listOf(700f, 520f, 360f, 0f)) {
                pick = ordered.firstOrNull { c -> taken.none { hypot(it.x - c.x, it.y - c.y) < sep } }
                if (pick != null) break
            }
            val p = pick ?: near.first()
            if (human == null) taken += Pt(p.x, p.y)
            val around = map.lootSpots.sortedBy { hypot(it.x - p.x, it.y - p.y) }.take(3)
            bots.forEachIndexed { k, b -> val h = around[k % around.size]; brains[b.id]?.setHome(h.x, h.y) }
        }
    }

    /** Back to the lobby with the same humans (rematch). */
    fun resetToLobby(waitS: Float = 6f) {
        fighters.values.removeAll { it.bot }
        for (f in fighters.values.toList()) fighters[f.id] = Fighter(f.id, f.name, f.characterId, false)
        brains.clear(); bullets.clear(); zombies.clear(); loot.clear(); airdrops.clear(); hitFx.clear(); feed.clear()
        phase = Phase.LOBBY; phaseT = waitS; winnerId = -1; winnerSquad = -1; banner = ""; matchTime = 0f
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
        updateRevives(dt)
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
        if (f.reviveBreakT > 0f) f.reviveBreakT -= dt
        val canAct = !f.downed
        // reviving: hold USE next to a downed teammate (it also means "swap weapon", but never while a teammate needs you)
        val mate = if (canAct) reviveCandidate(f) else null
        val prevRev = f.reviveTarget
        f.reviveTarget = if (mate != null && inp.use && f.reviveBreakT <= 0f) mate.id else -1
        if (f.reviveTarget >= 0 && f.reviveTarget != prevRev) statRevivesStarted++
        else if (f.reviveTarget < 0 && prevRev >= 0 && fighters[prevRev]?.downed == true) statRevivesInterrupted++
        if (f.reviveTarget >= 0 && f.healKind != 0) cancelHeal(f)
        // aim
        val al = hypot(inp.aimX, inp.aimY)
        if (al > 0.2f) f.aim = atan2(inp.aimY, inp.aimX)
        // reload
        if (f.reloading) { f.reloadLeft -= dt; if (f.reloadLeft <= 0f) { f.reloadLeft = 0f; f.rounds = f.weapon.mag } }
        else if (canAct && inp.reload && f.rounds < f.weapon.mag) f.reloadLeft = f.weapon.reload
        // heal channel
        if (f.healKind != 0) {
            if (!inp.heal || inp.fire) cancelHeal(f)
            else { f.healT += dt; if (f.healT >= f.healDuration) finishHeal(f) }
        } else if (canAct && inp.heal && !inp.fire && f.reviveTarget < 0) {
            val k = chooseHeal(f)
            if (k != 0) { f.healKind = k; f.healT = 0f }
        }
        // movement
        var dx = inp.dx; var dy = inp.dy
        val len = hypot(dx, dy); if (len > 1f) { dx /= len; dy /= len }
        val speed = SPEED * f.character.speedMult * when {
            f.downed -> if (f.beingRevived) 0f else CRAWL_SPEED
            f.reviveTarget >= 0 -> REVIVE_SLOW
            f.healKind != 0 -> 0.55f
            else -> 1f
        }
        f.kvx -= f.kvx * min(1f, 9f * dt); f.kvy -= f.kvy * min(1f, 9f * dt)
        val out = tmp
        map.resolve(f.x + (dx * speed + f.kvx) * dt, f.y + (dy * speed + f.kvy) * dt, BrConst.BODY_R, out)
        f.x = out[0]; f.y = out[1]
        // actions
        if (canAct && inp.ability && f.abilityCd <= 0f) useAbility(f)
        if (canAct && inp.use && f.useCd <= 0f && mate == null) { f.useCd = 0.35f; swapWeapon(f) }
        if (canAct && inp.fire && al > 0.2f && f.fireCd <= 0f && !f.reloading && f.healKind == 0) {
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
                    if (o === f || !o.alive || sameSquad(f, o)) continue
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
            if (sameSquad(a, b)) continue // teammates never block or push each other
            val dx = b.x - a.x; val dy = b.y - a.y; val d = hypot(dx, dy); val min = BrConst.BODY_R * 2f
            if (d >= min) continue
            val nx = if (d > 0.01f) dx / d else 1f; val ny = if (d > 0.01f) dy / d else 0f
            val push = (min - d) / 2f
            map.resolve(a.x - nx * push, a.y - ny * push, BrConst.BODY_R, tmp); a.x = tmp[0]; a.y = tmp[1]
            map.resolve(b.x + nx * push, b.y + ny * push, BrConst.BODY_R, tmp); b.x = tmp[0]; b.y = tmp[1]
        }
    }

    // ---- Damage -------------------------------------------------------------------------------------------------
    fun sameSquad(a: Fighter?, b: Fighter?) = a != null && b != null && a.squad >= 0 && a.squad == b.squad

    /** Applies damage. Source id < 0 is the environment ([-1] zone, [-2] horde). Returns true if it eliminated the target (going down is not a kill). */
    fun damage(t: Fighter, amount: Float, src: Int, srcName: String, ignoreShield: Boolean = false, interrupt: Boolean = true, fx: Boolean = true): Boolean {
        if (!t.alive || t.protectedT > 0f || amount <= 0f || phase != Phase.LIVE) return false
        if (src >= 0 && src != t.id && sameSquad(fighters[src], t)) return false // no friendly fire, whatever the weapon
        if (t.downed) return hurtDowned(t, amount, src, srcName, fx)
        var a = amount * (if (t.reduceT > 0f) 0.5f else 1f)
        val dealt = a
        if (!ignoreShield && t.shield > 0f) { val s = min(t.shield, a); t.shield -= s; a -= s }
        t.hp -= a
        if (interrupt) { if (t.healKind != 0) cancelHeal(t); t.reviveBreakT = REVIVE_BREAK }
        t.killerId = src; t.killedBy = srcName
        val dead = t.hp <= 0f
        val goesDown = dead && canGoDown(t)
        if (fx && dealt >= 1f) hitFx += HitFx(hitSeq++, t.x, t.y, dealt.toInt(), src, t.id, dead && !goesDown)
        if (goesDown) goDown(t, src) else if (dead) eliminate(t, src, srcName, null)
        return dead && !goesDown
    }

    /** A hit on a downed fighter shortens their bleed-out instead of costing health, so reviving under fire is a real risk. */
    private fun hurtDowned(t: Fighter, amount: Float, src: Int, srcName: String, fx: Boolean): Boolean {
        t.downedT -= amount * BLEED_PER_DMG
        if (src >= 0) { t.killerId = src; t.killedBy = srcName }
        val dead = t.downedT <= 0f
        if (fx && amount >= 1f) hitFx += HitFx(hitSeq++, t.x, t.y, amount.toInt(), src, t.id, dead)
        if (dead) { statBleedOuts++; eliminate(t, t.killerId, t.killedBy, null) }
        return dead
    }

    /** Going down needs a teammate who can still move (a downed one cannot revive anybody). */
    private fun canGoDown(t: Fighter) = squadSize > 1 && fighters.values.any { it !== t && it.alive && !it.downed && sameSquad(it, t) }

    private fun goDown(t: Fighter, src: Int) {
        t.downed = true; t.hp = 0f; t.shield = 0f; t.downedT = BLEED_TIME; t.reviveP = 0f; t.reviveTarget = -1; t.reviveBreakT = 0f
        cancelHeal(t); statDowns++
        val by = fighters[src]?.takeIf { it !== t }
        announce(if (by != null) "${t.name} was downed by ${by.name}" else "${t.name} is down")
    }

    /** The nearest downed teammate within reach, or null. */
    private fun reviveCandidate(f: Fighter): Fighter? {
        var best: Fighter? = null; var bd = REVIVE_RANGE
        for (o in fighters.values) {
            if (o === f || !o.alive || !o.downed || !sameSquad(f, o)) continue
            val d = hypot(o.x - f.x, o.y - f.y); if (d <= bd) { bd = d; best = o }
        }
        return best
    }

    /** Revive progress (and the bleed-out clock, which pauses while somebody is working on the downed fighter). */
    private fun updateRevives(dt: Float) {
        for (d in fighters.values) {
            if (!d.alive || !d.downed) continue
            val rv = fighters.values.firstOrNull { it.alive && !it.downed && it.reviveTarget == d.id && it.reviveBreakT <= 0f }
            d.beingRevived = rv != null
            if (rv != null) {
                d.reviveP += dt / REVIVE_TIME
                if (d.reviveP >= 1f) revive(d, rv)
            } else {
                d.reviveP = max(0f, d.reviveP - dt / REVIVE_TIME * REVIVE_DECAY)
                d.downedT -= dt
                if (d.downedT <= 0f) { statBleedOuts++; eliminate(d, d.killerId, d.killedBy, null) }
            }
        }
    }

    private fun revive(d: Fighter, by: Fighter) {
        d.downed = false; d.beingRevived = false; d.hp = d.maxHp * REVIVE_HP; d.shield = 0f; d.reviveP = 0f; d.downedT = 0f; d.killerId = -1; d.killedBy = ""
        by.reviveTarget = -1; by.revives++; statRevives++
        announce("${by.name} revived ${d.name}")
    }

    /** Squads that still have a fighter in the match (downed counts). */
    fun squadsAlive(): Int {
        var n = 0
        for (f in fighters.values) {
            if (!f.alive) continue
            var seen = false
            for (o in fighters.values) { if (o === f) break; if (o.alive && o.squad == f.squad) { seen = true; break } }
            if (!seen) n++
        }
        return n
    }

    private fun eliminate(t: Fighter, src: Int, srcName: String, text: String?) {
        if (!t.alive) return
        val place = squadsAlive() // the squad's placement if this wipes it: squads still in the match right now
        t.alive = false; t.hp = 0f; t.downed = false; t.reviveTarget = -1; cancelHeal(t)
        t.placement = place
        val killer = fighters[src]
        if (killer != null && killer !== t) killer.kills++
        dropWeapon(t)
        loot += Loot(nextId++, LootKind.CELL, t.x - 10f, t.y, null)
        announce(text ?: when {
            killer != null && killer !== t -> "${killer.name} eliminated ${t.name} (${srcName})"
            src == -1 -> "${t.name} was claimed by the Dead Zone"
            src == -2 -> "${t.name} was eaten by the horde"
            else -> if (squadSize > 1) "${t.name} bled out" else "${t.name} is out"
        })
        squadCheck(t.squad, place)
    }

    /** A squad with nobody left who can move cannot revive anyone: its downed fighters are out, and a wiped squad shares one placement. */
    private fun squadCheck(sq: Int, place: Int) {
        if (fighters.values.none { it.alive && !it.downed && it.squad == sq }) {
            for (m in fighters.values.toList()) if (m.alive && m.downed && m.squad == sq) eliminate(m, m.killerId, m.killedBy, null)
        }
        if (fighters.values.none { it.alive && it.squad == sq }) for (m in fighters.values) if (m.squad == sq) m.placement = place
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
            val shooter = fighters[b.owner]
            for (f in fighters.values) {
                if (!f.alive || f.id == b.owner || f.id in b.hit || sameSquad(shooter, f)) continue
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
        val shooter = fighters[b.owner]
        for (f in fighters.values) {
            if (!f.alive || f.id == b.owner || f.id in b.hit || sameSquad(shooter, f)) continue
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
            val f = fighters.values.firstOrNull { o -> o.alive && !o.downed && hypot(o.x - l.x, o.y - l.y) < AUTO_PICKUP && (if (l.kind == LootKind.MEDKIT) o.medkits < CARRY else o.cells < CARRY) } ?: continue
            if (l.kind == LootKind.MEDKIT) f.medkits++ else f.cells++
            it.remove()
        }
    }

    // ---- End of match -------------------------------------------------------------------------------------------
    private fun checkEnd() {
        val alive = fighters.values.filter { it.alive }
        val humansLeft = alive.any { !it.bot }
        val hadHumans = fighters.values.any { !it.bot }
        val squadsLeft = squadsAlive()
        if (squadsLeft > 1 && (humansLeft || !hadHumans)) return
        phase = Phase.ENDED; phaseT = 3f
        if (squadsLeft == 1) {
            val sq = alive.first().squad
            winnerSquad = sq
            for (m in fighters.values) if (m.squad == sq) m.placement = 1
            val winner = alive.firstOrNull { !it.bot } ?: alive.first()
            winnerId = winner.id
            say(if (squadSize > 1) "${winner.name}'s squad is the last one standing!" else "${winner.name} is the last one standing!", 999f)
        } else {
            winnerId = -1
            say(if (squadsLeft == 0 || squadSize <= 1) "Nobody survived the Blackout" else "Every human squad was wiped out", 999f)
        }
    }

    // ---- Snapshot -----------------------------------------------------------------------------------------------
    fun snapshot(viewerId: Int): BrSnapshot {
        val me = fighters[viewerId]
        var focus = me
        if (me != null && !me.alive && phase == Phase.LIVE) {
            focus = fighters[me.spectate]?.takeIf { it.alive } ?: followMate(me) ?: fighters[me.killerId]?.takeIf { it.alive } ?: fighters.values.firstOrNull { it.alive && !it.bot } ?: fighters.values.firstOrNull { it.alive }
            me.spectate = focus?.id ?: -1
        }
        val camX = focus?.x ?: me?.x ?: BrConst.CENTER; val camY = focus?.y ?: me?.y ?: BrConst.CENTER
        fun near(x: Float, y: Float) = hypot(x - camX, y - camY) <= BrConst.VIEW_RANGE
        // squad mates are always sent (the squad panel and the minimap show them wherever they are)
        val fs = fighters.values.filter { phase == Phase.LOBBY || it.id == viewerId || it === focus || (it.alive && (near(it.x, it.y) || (squadSize > 1 && sameSquad(it, me)))) }
            .map { f ->
                BrFighterSnap(
                    f.id, f.name, f.characterId, f.x, f.y, f.aim, f.hp, f.maxHp, f.shield, BrGuns.index(f.weapon.gun), f.weapon.rarity.ordinal, f.rounds, f.reloading, f.healKind != 0, f.alive, f.protectedT > 0f, f.reduceT > 0f,
                    f.squad, f.downed, if (f.downed) (f.downedT / BLEED_TIME).coerceIn(0f, 1f) else 0f, f.reviveP.coerceIn(0f, 1f), f.reviveTarget >= 0,
                )
            }
        val lobbyNames = if (phase == Phase.LOBBY) humans().map { it.name } else emptyList()
        val self = if (me == null) null else BrSelf(
            me.alive, me.kills, me.placement, me.medkits, me.cells, max(0f, me.abilityCd), if (me.healKind != 0) me.healT / me.healDuration else 0f,
            prompt(me), if (!me.alive) (focus?.name ?: "") else "", me.weapon.mag, max(0f, me.reloadLeft / max(0.01f, me.weapon.reload)),
            me.squad, me.downed, selfRevive(me), if (me.downed) (me.downedT / BLEED_TIME).coerceIn(0f, 1f) else 0f, fighters.values.filter { sameSquad(it, me) }.sumOf { it.kills },
        )
        val hits = hitFx.filter { it.src == viewerId || it.dst == viewerId }.map { BrHitSnap(it.seq, it.x, it.y, it.amount, it.src == viewerId, it.dst == viewerId, it.kill) }
        return BrSnapshot(
            map.seed, phase.ordinal, when (phase) { Phase.LOBBY -> phaseT; Phase.DEPLOY -> phaseT; else -> 0f }, aliveCount(), if (phase == Phase.LOBBY) field else fighters.size,
            camX, camY, viewerId, focus?.id ?: -1,
            BrZoneSnap(zoneCx, zoneCy, zoneR, nextCx, nextCy, nextR, zoneTimeLeft, zoneShrinking, zoneDps, zoneIdx),
            self, fs,
            zombies.filter { near(it.x, it.y) }.map { BrZombieSnap(it.id, it.x, it.y) },
            bullets.filter { near(it.x, it.y) }.map { BrBulletSnap(it.x, it.y, atan2(it.vy, it.vx)) },
            loot.filter { near(it.x, it.y) }.map { BrLootSnap(it.id, it.kind.ordinal, it.x, it.y, it.weapon?.let { w -> BrGuns.index(w.gun) } ?: 0, it.weapon?.rarity?.ordinal ?: 0) },
            airdrops.map { BrAirdropSnap(it.x, it.y, it.t) }, hits, feed.map { it.text }.takeLast(5),
            if (bannerT > 0f || phase == Phase.ENDED) banner else "", fighters[winnerId]?.name ?: "", lobbyNames,
            squadSize, squadsAlive(), if (phase == Phase.LOBBY) 0 else squadCount,
        )
    }

    /** Progress bar value for the viewer: how far along their own revive of a mate is, or how far along their mate's revive of them is. */
    private fun selfRevive(me: Fighter): Float {
        if (me.downed) return me.reviveP.coerceIn(0f, 1f)
        val t = fighters[me.reviveTarget] ?: return 0f
        return t.reviveP.coerceIn(0f, 1f)
    }

    /** A living squad mate to watch after being eliminated: one who can still move first. */
    private fun followMate(me: Fighter): Fighter? {
        var best: Fighter? = null
        for (o in fighters.values) if (o.alive && sameSquad(o, me) && (best == null || (best.downed && !o.downed))) best = o
        return best
    }

    private fun prompt(f: Fighter): String {
        if (!f.alive || f.downed) return ""
        reviveCandidate(f)?.let { return "REVIVE ${it.name}" }
        val l = loot.filter { it.kind == LootKind.WEAPON && hypot(it.x - f.x, it.y - f.y) < PICKUP_RANGE }.minByOrNull { hypot(it.x - f.x, it.y - f.y) } ?: return ""
        return "USE: swap to ${l.weapon!!.displayName}"
    }
}
