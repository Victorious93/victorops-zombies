package com.victorious.zombie.net

import com.victorious.zombie.br.BrCodec
import com.victorious.zombie.br.BrSnapshot
import com.victorious.zombie.logic.Characters
import com.victorious.zombie.sim.PlayerInput
import com.victorious.zombie.sim.Snapshot
import com.victorious.zombie.sim.SnapshotCodec
import com.victorious.zombie.sim.Sim
import com.victorious.zombie.sim.World
import java.util.concurrent.ConcurrentLinkedQueue

/** Wire message types. */
object Msg {
    const val JOIN = "zj"      // client -> host: "<characterId>"
    const val INPUT = "zi"     // client -> host: PlayerInput text
    const val WELCOME = "zw"   // host -> client: "<playerId>" (Zombie Survival) or "<playerId>,<kind>" (e.g. "2,royale")
    const val STATE = "zs"     // host -> client: Snapshot base64
    const val ROYALE_STATE = "zr" // host -> client: Blackout Royale snapshot base64
    const val FULL = "zf"      // host -> client: lobby full
    const val BYE = "zb"       // client -> host: leaving the game (the link itself may stay up, e.g. a shared Connect session)
}

/**
 * Host side: owns the [Sim] and talks to every connected peer. The host's own player is id [HOST_ID].
 * Call [tick] once per frame from the game thread; network callbacks only enqueue.
 */
class HostSession(val sim: Sim, private val sendHz: Float = 15f) {
    /** The Zombie Survival world. Only valid when [sim] is one. */
    val world: World get() = sim as World

    companion object {
        const val HOST_ID = 0
        /** A fresh Zombie Survival world with the host's own player already in it. */
        fun create(hostCharacter: com.victorious.zombie.logic.Character): HostSession =
            HostSession(World().also { it.addPlayer(HOST_ID, hostCharacter) })

        /**
         * A fresh Blackout Royale lobby with the host in it. [autoStartS] is how long the lobby waits for the host to
         * start (solo play uses a short wait; hosting for friends a long one).
         */
        fun createRoyale(hostCharacter: com.victorious.zombie.logic.Character, autoStartS: Float = 1.5f, skill: com.victorious.zombie.br.BotSkill = com.victorious.zombie.br.BotSkill.NORMAL, squadSize: Int = 1): HostSession =
            HostSession(com.victorious.zombie.br.BrWorld(autoStartS = autoStartS, botSkill = skill, squadSize = squadSize).also { it.join(HOST_ID, hostCharacter.id) })
    }

    private class Peer(val id: Int, val link: NetLink)
    private sealed class Event { class Join(val link: NetLink) : Event(); class Msg(val link: NetLink, val type: String, val data: String) : Event(); class Closed(val link: NetLink) : Event() }

    private val events = ConcurrentLinkedQueue<Event>()
    private val peers = LinkedHashMap<NetLink, Peer>()
    private var sendT = 0f
    val peerCount: Int get() = peers.size

    /** Thread-safe: may be called from a socket accept thread. */
    fun attach(link: NetLink) {
        link.listener = object : NetLink.Listener {
            override fun onMessage(type: String, data: String) { events.add(Event.Msg(link, type, data)) }
            override fun onClosed() { events.add(Event.Closed(link)) }
        }
        events.add(Event.Join(link))
    }

    fun tick(dt: Float) {
        while (true) {
            when (val e = events.poll() ?: break) {
                is Event.Join -> { /* wait for the JOIN message so we know the character */ }
                is Event.Msg -> handle(e.link, e.type, e.data)
                is Event.Closed -> peers.remove(e.link)?.let { sim.leave(it.id) }
            }
        }
        sim.step(dt)
        sendT += dt
        if (sendT >= 1f / sendHz) {
            sendT = 0f
            for (p in peers.values) p.link.send(sim.stateType, sim.stateText(p.id))
        }
    }

    private fun handle(link: NetLink, type: String, data: String) {
        val peer = peers[link]
        when (type) {
            Msg.JOIN -> if (peer == null) {
                val id = (1..World.MAX_PLAYERS).firstOrNull { cand -> !sim.hasPlayer(cand) && peers.values.none { it.id == cand } }
                if (id == null || !sim.join(id, data.trim())) { link.send(Msg.FULL, "full"); link.close() }
                else { peers[link] = Peer(id, link); link.send(Msg.WELCOME, sim.kind?.let { "$id,$it" } ?: id.toString()) }
            }
            Msg.INPUT -> if (peer != null) PlayerInput.fromText(data)?.let { sim.applyInput(peer.id, it) }
            Msg.BYE -> if (peer != null) { peers.remove(link); sim.leave(peer.id) }
        }
    }

    fun close() { peers.keys.toList().forEach { it.close() }; peers.clear() }
}

/** Client side: sends inputs, keeps the latest snapshot. Safe to read [latest] from the render thread. */
class ClientSession(private val link: NetLink, private val characterId: String, private val inputHz: Float = 20f) {
    @Volatile var latest: Snapshot? = null; private set
    /** Latest Blackout Royale frame (when the host runs that game). */
    @Volatile var latestRoyale: BrSnapshot? = null; private set
    /** Which game the host runs: null = Zombie Survival (or not welcomed yet, see [playerId]), "royale" = Blackout Royale. */
    @Volatile var kind: String? = null; private set
    @Volatile var playerId: Int = -1; private set
    @Volatile var connected = true; private set
    @Volatile var rejected = false; private set
    private var sendT = 0f
    private var joinT = 0f

    init {
        link.listener = object : NetLink.Listener {
            override fun onMessage(type: String, data: String) {
                when (type) {
                    Msg.WELCOME -> {
                        val parts = data.trim().split(',', limit = 2)
                        parts[0].toIntOrNull()?.let { kind = parts.getOrNull(1)?.takeIf { k -> k.isNotBlank() }; playerId = it }
                    }
                    Msg.STATE -> try { latest = SnapshotCodec.fromText(data) } catch (_: Exception) { /* drop bad packet */ }
                    Msg.ROYALE_STATE -> try { latestRoyale = BrCodec.fromText(data) } catch (_: Exception) { /* drop bad packet */ }
                    Msg.FULL -> rejected = true
                }
            }
            override fun onClosed() { connected = false }
        }
        link.send(Msg.JOIN, characterId)
    }

    fun tick(dt: Float, input: PlayerInput) {
        sendT += dt
        if (sendT >= 1f / inputHz) { sendT = 0f; link.send(Msg.INPUT, input.toText()) }
        // A shared link has no handshake of its own, so the host may not have been listening for the first JOIN. Repeat it until welcomed.
        if (playerId < 0 && !rejected && connected) { joinT += dt; if (joinT >= JOIN_RETRY_S) { joinT = 0f; link.send(Msg.JOIN, characterId) } }
    }

    fun close() { link.send(Msg.BYE, "bye"); link.close() }

    private companion object { const val JOIN_RETRY_S = 1f }
}
