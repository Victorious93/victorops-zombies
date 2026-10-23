package com.victorious.zombie.sim

/**
 * A host-authoritative game the network layer can drive: [com.victorious.zombie.sim.World] (Zombie Survival)
 * or the Blackout Royale world. The session layer only needs these few verbs.
 */
interface Sim {
    /** Wire message type of this game's state messages (see [com.victorious.zombie.net.Msg]). */
    val stateType: String

    /** Extra tag sent in the WELCOME so a joining client knows which screen to open; null for Zombie Survival (wire-compatible). */
    val kind: String?

    fun hasPlayer(id: Int): Boolean

    /** Adds a human. False if the game is full, already running and not joinable, or the id is taken. */
    fun join(id: Int, characterId: String): Boolean
    fun leave(id: Int)
    fun applyInput(id: Int, input: PlayerInput)
    fun step(dt: Float)

    /** The frame as seen by player [forId], as text-safe data for the wire. */
    fun stateText(forId: Int): String
}
