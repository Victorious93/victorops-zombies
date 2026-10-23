package com.victorious.zombie.fps

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

enum class Tile { VOID, OUTSIDE, FLOOR, WALL, WINDOW, DOOR, OBJECT }
enum class PropKind { WALL_BUY, BOX, PERK, POWER, FORGE }

/** A boarded window: zombies come from the [outX],[outY] tile, tear the boards and climb into [inX],[inY]. */
class Window(val id: Int, val tx: Int, val ty: Int, val inX: Int, val inY: Int, val outX: Int, val outY: Int, val zone: Int) {
    var boards = MAX_BOARDS
    companion object { const val MAX_BOARDS = 6 }
}

class Door(val id: Int, val tx: Int, val ty: Int, val zoneA: Int, val zoneB: Int, val cost: Int) { var open = false }

/** Something to use: [fx],[fy] is the direction from the prop's tile to the floor tile in front of it. */
class Prop(val kind: PropKind, val tx: Int, val ty: Int, val zone: Int, val fx: Int, val fy: Int, val gun: FpsGun? = null, val perk: Perk? = null)

/**
 * The Zombies 3D map: a grid of 2 m tiles parsed from text. World units are metres; the sim plane is (x, y) and the renderer maps
 * y to 3D z. Zones are rooms opened by buying [Door]s. Pure data and geometry, no rendering.
 */
class FpsMap(rows: List<String> = STATION) {
    companion object {
        const val CELL = 2f
        const val WALL_H = 3.2f

        /**
         * "Station 9" (original). Legend: o outside (zombies only), # wall, 0-3 floor of zone n, S start (zone 0), W window,
         * D door, wall-buys on walls (r Ranger, g Trench, k Kestrel, a Harrow), props on floor (B box, P power, F forge,
         * perks I Ironhide, Q Quickhand, R Rapidfire, V Second Wind).
         */
        val STATION = listOf(
            "oooooooooooooooooooooooo",
            "o##W#########W##k##W###o",
            "o#I3333P#Q111111111111#o",
            "o#333333#1111111111111Wo",
            "o#333333D1111111111111#o",
            "oW333333#11111111111B1#o",
            "o#333333#1111111111111#o",
            "o##########D###########o",
            "ooooo#F0000000V#222222#o",
            "ooooo#000000000#222222ao",
            "oooooW000000000D222222#o",
            "ooooo#0000S0000#222222#o",
            "ooooor000000000#222222Wo",
            "ooooo#000000000#222222#o",
            "ooooo##g##W#####222222#o",
            "oooooooooooooooW22222R#o",
            "ooooooooooooooo###W####o",
            "oooooooooooooooooooooooo",
        )
        private val DOOR_COSTS = mapOf(setOf(0, 1) to 750, setOf(0, 2) to 1000, setOf(1, 3) to 1250)
        private val WALL_BUYS = mapOf('r' to FpsGuns.RANGER, 'g' to FpsGuns.TRENCH, 'k' to FpsGuns.KESTREL, 'a' to FpsGuns.HARROW)
        private val PERKS = mapOf('I' to Perk.IRONHIDE, 'Q' to Perk.QUICKHAND, 'R' to Perk.RAPIDFIRE, 'V' to Perk.SECOND_WIND)
        private val DX = intArrayOf(1, -1, 0, 0); private val DY = intArrayOf(0, 0, 1, -1)
    }

    val w = rows.maxOf { it.length }
    val h = rows.size
    val tiles = Array(w * h) { Tile.VOID }
    /** Zone of each floor tile (and of props, doors and windows: the room they belong to), -1 otherwise. */
    val zone = IntArray(w * h) { -1 }
    val windows = ArrayList<Window>(); val doors = ArrayList<Door>(); val props = ArrayList<Prop>()
    val zoneCount: Int
    var startX = 0f; private set
    var startY = 0f; private set
    private val doorAt = HashMap<Int, Door>(); private val windowAt = HashMap<Int, Window>()

    init {
        val marks = ArrayList<Triple<Char, Int, Int>>()
        for (y in 0 until h) for (x in 0 until w) {
            val c = rows[y].getOrElse(x) { ' ' }
            val i = y * w + x
            tiles[i] = when (c) {
                'o' -> Tile.OUTSIDE
                '#' -> Tile.WALL
                in '0'..'9' -> { zone[i] = c - '0'; Tile.FLOOR }
                'S' -> { zone[i] = 0; startX = (x + 0.5f) * CELL; startY = (y + 0.5f) * CELL; Tile.FLOOR }
                'W' -> { marks += Triple(c, x, y); Tile.WINDOW }
                'D' -> { marks += Triple(c, x, y); Tile.DOOR }
                in WALL_BUYS.keys -> { marks += Triple(c, x, y); Tile.WALL }
                'B', 'P', 'F', in PERKS.keys -> { marks += Triple(c, x, y); Tile.OBJECT }
                else -> Tile.VOID
            }
        }
        zoneCount = zone.max() + 1
        for ((c, x, y) in marks) {
            val floors = (0 until 4).filter { at(x + DX[it], y + DY[it]) == Tile.FLOOR }
            when (c) {
                'W' -> {
                    val inD = floors.single(); val outD = (0 until 4).single { at(x + DX[it], y + DY[it]) == Tile.OUTSIDE }
                    val win = Window(windows.size, x, y, x + DX[inD], y + DY[inD], x + DX[outD], y + DY[outD], zoneAt(x + DX[inD], y + DY[inD]))
                    zone[y * w + x] = win.zone; windows += win; windowAt[y * w + x] = win
                }
                'D' -> {
                    val zs = floors.map { zoneAt(x + DX[it], y + DY[it]) }.distinct()
                    require(zs.size == 2) { "door at $x,$y must join two zones" }
                    val d = Door(doors.size, x, y, zs[0], zs[1], DOOR_COSTS[zs.toSet()] ?: 1000)
                    doors += d; doorAt[y * w + x] = d
                }
                else -> {
                    // face the open side: for corner props, the side toward the middle of the room
                    val zn = zoneAt(x + DX[floors.first()], y + DY[floors.first()])
                    val (cx, cy) = zoneCentre(zn)
                    val f = floors.maxBy { DX[it] * (cx - x) + DY[it] * (cy - y) }
                    zone[y * w + x] = zn
                    val kind = when (c) { 'B' -> PropKind.BOX; 'P' -> PropKind.POWER; 'F' -> PropKind.FORGE; in PERKS.keys -> PropKind.PERK; else -> PropKind.WALL_BUY }
                    props += Prop(kind, x, y, zn, DX[f], DY[f], WALL_BUYS[c], PERKS[c])
                }
            }
        }
    }

    private fun zoneCentre(z: Int): Pair<Float, Float> {
        var sx = 0f; var sy = 0f; var n = 0
        for (y in 0 until h) for (x in 0 until w) if (zone[y * w + x] == z && tiles[y * w + x] == Tile.FLOOR) { sx += x; sy += y; n++ }
        return sx / max(1, n) to sy / max(1, n)
    }

    fun inside(x: Int, y: Int) = x in 0 until w && y in 0 until h
    fun at(x: Int, y: Int): Tile = if (inside(x, y)) tiles[y * w + x] else Tile.VOID
    fun zoneAt(x: Int, y: Int): Int = if (inside(x, y)) zone[y * w + x] else -1
    fun doorAt(x: Int, y: Int): Door? = doorAt[y * w + x]
    fun windowAt(x: Int, y: Int): Window? = windowAt[y * w + x]
    fun tileOf(v: Float) = floor(v / CELL).toInt()
    fun centre(t: Int) = (t + 0.5f) * CELL

    /** Where the player can stand: floor and open doors. */
    fun walkable(x: Int, y: Int): Boolean = when (at(x, y)) { Tile.FLOOR -> true; Tile.DOOR -> doorAt(x, y)!!.open; else -> false }
    /** Where zombies can be outside the building. */
    fun outsideWalk(x: Int, y: Int) = at(x, y) == Tile.OUTSIDE
    /** Bullets stop at walls, props, closed doors and the edge of the world. Windows and boards let bullets through. */
    fun stopsBullets(x: Int, y: Int): Boolean = when (at(x, y)) { Tile.WALL, Tile.OBJECT, Tile.VOID -> true; Tile.DOOR -> !doorAt(x, y)!!.open; else -> false }

    /**
     * Pushes a circle of radius [r] at ([x],[y]) out of every tile that [blocked] says is solid (two passes are enough for
     * corners). Writes the result to [out].
     */
    inline fun resolve(x: Float, y: Float, r: Float, out: FloatArray, blocked: (Int, Int) -> Boolean) {
        var px = x; var py = y
        repeat(2) {
            val tx0 = tileOf(px - r); val tx1 = tileOf(px + r); val ty0 = tileOf(py - r); val ty1 = tileOf(py + r)
            for (ty in ty0..ty1) for (tx in tx0..tx1) {
                if (!blocked(tx, ty)) continue
                val minX = tx * CELL; val minY = ty * CELL
                val cx = px.coerceIn(minX, minX + CELL); val cy = py.coerceIn(minY, minY + CELL)
                val dx = px - cx; val dy = py - cy; val d2 = dx * dx + dy * dy
                if (d2 >= r * r) continue
                if (d2 > 1e-8f) { val d = sqrt(d2); px = cx + dx / d * r; py = cy + dy / d * r }
                else { // centre inside the tile: leave by the nearest face
                    val l = px - minX; val rr = minX + CELL - px; val b = py - minY; val t = minY + CELL - py
                    val m = min(min(l, rr), min(b, t))
                    when (m) { l -> px = minX - r; rr -> px = minX + CELL + r; b -> py = minY - r; else -> py = minY + CELL + r }
                }
            }
        }
        out[0] = px; out[1] = py
    }

    /** Distance along a unit direction until a tile [stop] says is solid, up to [maxD] (grid DDA). */
    inline fun cast(x: Float, y: Float, dx: Float, dy: Float, maxD: Float, stop: (Int, Int) -> Boolean): Float {
        var tx = tileOf(x); var ty = tileOf(y)
        if (stop(tx, ty)) return 0f
        val stepX = if (dx > 0) 1 else -1; val stepY = if (dy > 0) 1 else -1
        val tdx = if (abs(dx) < 1e-6f) Float.MAX_VALUE else CELL / abs(dx)
        val tdy = if (abs(dy) < 1e-6f) Float.MAX_VALUE else CELL / abs(dy)
        var tmx = if (abs(dx) < 1e-6f) Float.MAX_VALUE else ((if (dx > 0) (tx + 1) * CELL - x else x - tx * CELL) / abs(dx))
        var tmy = if (abs(dy) < 1e-6f) Float.MAX_VALUE else ((if (dy > 0) (ty + 1) * CELL - y else y - ty * CELL) / abs(dy))
        while (true) {
            val t: Float
            if (tmx < tmy) { t = tmx; tmx += tdx; tx += stepX } else { t = tmy; tmy += tdy; ty += stepY }
            if (t > maxD) return maxD
            if (stop(tx, ty)) return t
        }
    }

    /** True when a body of radius [r] can go straight from a to b without touching a tile [stop] blocks (three parallel rays). */
    inline fun clearPath(ax: Float, ay: Float, bx: Float, by: Float, r: Float, stop: (Int, Int) -> Boolean): Boolean {
        val d = hypot(bx - ax, by - ay); if (d < 1e-3f) return true
        val ux = (bx - ax) / d; val uy = (by - ay) / d
        for (k in -1..1) {
            val ox = -uy * r * k; val oy = ux * r * k
            if (cast(ax + ox, ay + oy, ux, uy, d, stop) < d) return false
        }
        return true
    }

    // ---- navigation ---------------------------------------------------------------------------------------------
    /** Steps from each walkable tile to the target tile (-1 = unreachable). Rebuilt by [flowTo]; 8-connected, no corner cutting. */
    val flow = IntArray(w * h) { -1 }
    private val queue = IntArray(w * h)
    var flowTarget = -1; private set

    fun flowTo(tx: Int, ty: Int) {
        java.util.Arrays.fill(flow, -1)
        flowTarget = ty * w + tx
        if (!inside(tx, ty)) return
        var head = 0; var tail = 0
        flow[flowTarget] = 0; queue[tail++] = flowTarget
        while (head < tail) {
            val i = queue[head++]; val x = i % w; val y = i / w
            for (dy in -1..1) for (dx in -1..1) {
                if (dx == 0 && dy == 0) continue
                val nx = x + dx; val ny = y + dy
                if (!walkable(nx, ny)) continue
                if (dx != 0 && dy != 0 && (!walkable(x + dx, y) || !walkable(x, y + dy))) continue
                val j = ny * w + nx
                if (flow[j] >= 0) continue
                flow[j] = flow[i] + 1; queue[tail++] = j
            }
        }
    }

    /** Outside fields: steps over outside tiles to each window's outer tile, so zombies can find their window. */
    val outsideFlow: List<IntArray> = windows.map { win ->
        val f = IntArray(w * h) { -1 }; val q = IntArray(w * h); var head = 0; var tail = 0
        val s = win.outY * w + win.outX; f[s] = 0; q[tail++] = s
        while (head < tail) {
            val i = q[head++]; val x = i % w; val y = i / w
            for (k in 0 until 4) { val nx = x + DX[k]; val ny = y + DY[k]; if (!outsideWalk(nx, ny)) continue; val j = ny * w + nx; if (f[j] >= 0) continue; f[j] = f[i] + 1; q[tail++] = j }
        }
        f
    }

    /** All zones reachable from zone 0 if every door were open (map sanity check for tests). */
    fun zonesConnected(): Boolean {
        val seen = BooleanArray(zoneCount); seen[0] = true
        var changed = true
        while (changed) { changed = false; for (d in doors) if (seen[d.zoneA] != seen[d.zoneB]) { seen[d.zoneA] = true; seen[d.zoneB] = true; changed = true } }
        return seen.all { it }
    }
}
