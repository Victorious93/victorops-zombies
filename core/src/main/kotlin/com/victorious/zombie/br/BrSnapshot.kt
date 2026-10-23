package com.victorious.zombie.br

import com.badlogic.gdx.utils.Base64Coder
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import kotlin.math.PI
import kotlin.math.roundToInt

class BrFighterSnap(
    val id: Int, val name: String, val characterId: String, val x: Float, val y: Float, val aim: Float,
    val hp: Float, val maxHp: Float, val shield: Float, val gunIndex: Int, val rarity: Int, val rounds: Int,
    val reloading: Boolean, val healing: Boolean, val alive: Boolean, val protectedNow: Boolean, val reduced: Boolean,
    val squad: Int = 0, val downed: Boolean = false, val bleed: Float = 0f, val reviveP: Float = 0f, val reviving: Boolean = false,
)
class BrZombieSnap(val id: Int, val x: Float, val y: Float)
class BrBulletSnap(val x: Float, val y: Float, val angle: Float)
class BrLootSnap(val id: Int, val kind: Int, val x: Float, val y: Float, val gunIndex: Int, val rarity: Int)
class BrAirdropSnap(val x: Float, val y: Float, val t: Float)
/** A damage number: [mine] = dealt by the viewer, [hurt] = taken by the viewer. */
class BrHitSnap(val seq: Int, val x: Float, val y: Float, val amount: Int, val mine: Boolean, val hurt: Boolean, val kill: Boolean)
class BrZoneSnap(
    val cx: Float, val cy: Float, val r: Float, val nextCx: Float, val nextCy: Float, val nextR: Float,
    val timeLeft: Float, val shrinking: Boolean, val dps: Float, val stage: Int,
)
/** The viewer's own state (null for an unknown viewer). */
class BrSelf(
    val alive: Boolean, val kills: Int, val placement: Int, val medkits: Int, val cells: Int, val abilityCd: Float, val healProgress: Float,
    val prompt: String, val spectating: String, val magSize: Int, val reloadProgress: Float,
    val squad: Int = 0, val downed: Boolean = false, val reviveProgress: Float = 0f, val bleed: Float = 0f, val squadKills: Int = 0,
)

/** Everything a screen needs to draw one frame for one viewer. Positions are what is near the camera only. */
class BrSnapshot(
    val seed: Int, val phase: Int, val timer: Float, val alive: Int, val field: Int,
    val camX: Float, val camY: Float, val meId: Int, val focusId: Int,
    val zone: BrZoneSnap, val self: BrSelf?,
    val fighters: List<BrFighterSnap>, val zombies: List<BrZombieSnap>, val bullets: List<BrBulletSnap>, val loot: List<BrLootSnap>,
    val airdrops: List<BrAirdropSnap>, val hits: List<BrHitSnap>, val feed: List<String>,
    val banner: String, val winner: String, val lobby: List<String>,
    /** Fighters per squad (1 = free-for-all), squads still in the match, and squads in the match. */
    val squadSize: Int = 1, val squadsAlive: Int = 0, val squads: Int = 0,
)

/** Compact binary form: positions are 16-bit fixed point, health bytes, angles bytes. Decoding untrusted bytes throws on garbage. */
object BrCodec {
    private const val MAX_ENTITIES = 400
    private const val POS = 20f // 3200 * 20 < 65535

    private fun DataOutputStream.pos(v: Float) = writeShort((v.coerceIn(0f, BrConst.SIZE) * POS).roundToInt())
    private fun DataInputStream.pos(): Float = readUnsignedShort() / POS
    private fun DataOutputStream.ang(v: Float) = writeByte((((v / (2 * PI.toFloat())) % 1f + 1f) % 1f * 256f).toInt() and 0xFF)
    private fun DataInputStream.ang(): Float = readUnsignedByte() / 256f * 2 * PI.toFloat()
    private fun DataOutputStream.str(s: String) = writeUTF(if (s.length > 80) s.substring(0, 80) else s)

    fun encode(s: BrSnapshot): ByteArray {
        val bo = ByteArrayOutputStream(2048)
        DataOutputStream(bo).use { o ->
            o.writeInt(s.seed); o.writeByte(s.phase); o.writeFloat(s.timer); o.writeByte(s.alive); o.writeByte(s.field)
            o.pos(s.camX); o.pos(s.camY); o.writeByte(s.meId and 0xFF); o.writeByte(s.focusId and 0xFF)
            val z = s.zone
            o.writeFloat(z.cx); o.writeFloat(z.cy); o.writeFloat(z.r); o.writeFloat(z.nextCx); o.writeFloat(z.nextCy); o.writeFloat(z.nextR)
            o.writeFloat(z.timeLeft); o.writeBoolean(z.shrinking); o.writeFloat(z.dps); o.writeByte(z.stage)
            val me = s.self
            o.writeBoolean(me != null)
            if (me != null) {
                o.writeBoolean(me.alive); o.writeByte(me.kills); o.writeByte(me.placement); o.writeByte(me.medkits); o.writeByte(me.cells)
                o.writeFloat(me.abilityCd); o.writeFloat(me.healProgress); o.str(me.prompt); o.str(me.spectating); o.writeByte(me.magSize); o.writeFloat(me.reloadProgress)
                o.writeByte(me.squad and 0xFF); o.writeBoolean(me.downed); o.writeFloat(me.reviveProgress); o.writeFloat(me.bleed); o.writeByte(me.squadKills.coerceIn(0, 255))
            }
            o.writeByte(s.fighters.size)
            for (f in s.fighters) {
                o.writeByte(f.id); o.str(f.name); o.str(f.characterId); o.pos(f.x); o.pos(f.y); o.ang(f.aim)
                o.writeByte(f.hp.roundToInt().coerceIn(0, 255)); o.writeByte(f.maxHp.roundToInt().coerceIn(1, 255)); o.writeByte(f.shield.roundToInt().coerceIn(0, 255))
                o.writeByte(f.gunIndex); o.writeByte(f.rarity); o.writeByte(f.rounds.coerceIn(0, 255))
                o.writeByte((if (f.reloading) 1 else 0) or (if (f.healing) 2 else 0) or (if (f.alive) 4 else 0) or (if (f.protectedNow) 8 else 0) or (if (f.reduced) 16 else 0) or (if (f.downed) 32 else 0) or (if (f.reviving) 64 else 0))
                o.writeByte(f.squad and 0xFF); o.writeByte((f.bleed.coerceIn(0f, 1f) * 255f).roundToInt()); o.writeByte((f.reviveP.coerceIn(0f, 1f) * 255f).roundToInt())
            }
            o.writeShort(s.zombies.size); for (zb in s.zombies) { o.writeShort(zb.id and 0xFFFF); o.pos(zb.x); o.pos(zb.y) }
            o.writeShort(s.bullets.size); for (b in s.bullets) { o.pos(b.x); o.pos(b.y); o.ang(b.angle) }
            o.writeShort(s.loot.size); for (l in s.loot) { o.writeShort(l.id and 0xFFFF); o.writeByte(l.kind); o.pos(l.x); o.pos(l.y); o.writeByte(l.gunIndex); o.writeByte(l.rarity) }
            o.writeByte(s.airdrops.size); for (a in s.airdrops) { o.pos(a.x); o.pos(a.y); o.writeFloat(a.t) }
            o.writeByte(s.hits.size)
            for (h in s.hits) { o.writeShort(h.seq and 0xFFFF); o.pos(h.x); o.pos(h.y); o.writeShort(h.amount.coerceIn(0, 32767)); o.writeByte((if (h.mine) 1 else 0) or (if (h.hurt) 2 else 0) or (if (h.kill) 4 else 0)) }
            o.writeByte(s.feed.size); for (t in s.feed) o.str(t)
            o.str(s.banner); o.str(s.winner)
            o.writeByte(s.lobby.size); for (n in s.lobby) o.str(n)
            o.writeByte(s.squadSize); o.writeByte(s.squadsAlive); o.writeByte(s.squads)
        }
        return bo.toByteArray()
    }

    fun decode(bytes: ByteArray): BrSnapshot {
        val i = DataInputStream(ByteArrayInputStream(bytes))
        fun count(): Int = i.readUnsignedShort().also { require(it <= MAX_ENTITIES) { "too many entities" } }
        val seed = i.readInt(); val phase = i.readUnsignedByte(); require(phase < Phase.values().size) { "bad phase" }
        val timer = i.readFloat(); val alive = i.readUnsignedByte(); val field = i.readUnsignedByte()
        val camX = i.pos(); val camY = i.pos(); val meId = i.readUnsignedByte().let { if (it == 255) -1 else it }; val focusId = i.readUnsignedByte().let { if (it == 255) -1 else it }
        val zone = BrZoneSnap(i.readFloat(), i.readFloat(), i.readFloat(), i.readFloat(), i.readFloat(), i.readFloat(), i.readFloat(), i.readBoolean(), i.readFloat(), i.readUnsignedByte())
        val self = if (i.readBoolean()) BrSelf(i.readBoolean(), i.readUnsignedByte(), i.readUnsignedByte(), i.readUnsignedByte(), i.readUnsignedByte(), i.readFloat(), i.readFloat(), i.readUTF(), i.readUTF(), i.readUnsignedByte(), i.readFloat(),
            i.readUnsignedByte(), i.readBoolean(), i.readFloat(), i.readFloat(), i.readUnsignedByte()) else null
        val fighters = List(i.readUnsignedByte()) {
            val id = i.readUnsignedByte(); val name = i.readUTF(); val ch = i.readUTF(); val x = i.pos(); val y = i.pos(); val aim = i.ang()
            val hp = i.readUnsignedByte().toFloat(); val mhp = i.readUnsignedByte().toFloat(); val sh = i.readUnsignedByte().toFloat()
            val gun = i.readUnsignedByte(); val rar = i.readUnsignedByte().coerceIn(0, Rarity.values().size - 1); val rounds = i.readUnsignedByte(); val fl = i.readUnsignedByte()
            val sq = i.readUnsignedByte(); val bleed = i.readUnsignedByte() / 255f; val rev = i.readUnsignedByte() / 255f
            BrFighterSnap(id, name, ch, x, y, aim, hp, mhp, sh, gun, rar, rounds, fl and 1 != 0, fl and 2 != 0, fl and 4 != 0, fl and 8 != 0, fl and 16 != 0, sq, fl and 32 != 0, bleed, rev, fl and 64 != 0)
        }
        val zombies = List(count()) { BrZombieSnap(i.readUnsignedShort(), i.pos(), i.pos()) }
        val bullets = List(count()) { BrBulletSnap(i.pos(), i.pos(), i.ang()) }
        val loot = List(count()) { BrLootSnap(i.readUnsignedShort(), i.readUnsignedByte(), i.pos(), i.pos(), i.readUnsignedByte(), i.readUnsignedByte().coerceIn(0, Rarity.values().size - 1)) }
        val drops = List(i.readUnsignedByte()) { BrAirdropSnap(i.pos(), i.pos(), i.readFloat()) }
        val hits = List(i.readUnsignedByte()) { val seq = i.readUnsignedShort(); val x = i.pos(); val y = i.pos(); val amt = i.readUnsignedShort(); val fl = i.readUnsignedByte(); BrHitSnap(seq, x, y, amt, fl and 1 != 0, fl and 2 != 0, fl and 4 != 0) }
        val feed = List(i.readUnsignedByte()) { i.readUTF() }
        val banner = i.readUTF(); val winner = i.readUTF()
        val lobby = List(i.readUnsignedByte()) { i.readUTF() }
        val squadSize = i.readUnsignedByte().also { require(it in 1..BrWorld.MAX_SQUAD) { "bad squad size" } }; val squadsAlive = i.readUnsignedByte(); val squads = i.readUnsignedByte()
        return BrSnapshot(seed, phase, timer, alive, field, camX, camY, meId, focusId, zone, self, fighters, zombies, bullets, loot, drops, hits, feed, banner, winner, lobby, squadSize, squadsAlive, squads)
    }

    fun toText(s: BrSnapshot): String = String(Base64Coder.encode(encode(s)))
    fun fromText(t: String): BrSnapshot = decode(Base64Coder.decode(t))
}
