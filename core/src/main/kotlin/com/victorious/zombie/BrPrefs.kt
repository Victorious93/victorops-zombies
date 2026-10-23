package com.victorious.zombie

import com.badlogic.gdx.Gdx

/** Blackout Royale choices that survive between matches. Storage failures are ignored: the default is fine. */
object BrPrefs {
    private const val FILE = "victorops-zombies"; private const val KEY = "br.squadSize"
    /** Fighters per squad: 1 = free-for-all, 2..4 = squads with revives. */
    var squadSize = 3
        set(v) { field = v.coerceIn(1, 4); try { Gdx.app.getPreferences(FILE).putInteger(KEY, field).flush() } catch (_: Throwable) {} }

    fun load() { try { squadSize = Gdx.app.getPreferences(FILE).getInteger(KEY, squadSize) } catch (_: Throwable) {} }

    /** 1 -> 2 -> 3 -> 4 -> 1. */
    fun next(size: Int) = if (size >= 4) 1 else size + 1

    fun label(size: Int, fighters: Int = 12) = if (size <= 1) "FREE-FOR-ALL" else "SQUADS OF $size  (${(fighters + size - 1) / size} squads)"
}
