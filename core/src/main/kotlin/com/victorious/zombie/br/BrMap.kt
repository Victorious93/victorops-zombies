package com.victorious.zombie.br

import java.util.PriorityQueue
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/** Blackout Royale constants shared by the sim, the bots and the renderer. */
object BrConst {
    const val SIZE = 3200f
    const val CENTER = SIZE / 2
    const val BODY_R = 14f
    const val ZOMBIE_R = 15f
    /** Fighters per match (humans + bots). */
    const val FIELD = 12
    /** Entities farther than this from the viewer are not sent (fog of war, and small snapshots). */
    const val VIEW_RANGE = 900f
}

class Pt(val x: Float, val y: Float)

class Rect(val x: Float, val y: Float, val w: Float, val h: Float) {
    val x2: Float get() = x + w
    val y2: Float get() = y + h

    fun overlaps(o: Rect, margin: Float = 0f) = x - margin < o.x2 && x2 + margin > o.x && y - margin < o.y2 && y2 + margin > o.y
    fun inflated(m: Float) = Rect(x - m, y - m, w + 2 * m, h + 2 * m)
    fun distSq(px: Float, py: Float): Float {
        val dx = px - px.coerceIn(x, x2); val dy = py - py.coerceIn(y, y2); return dx * dx + dy * dy
    }
}

class Poi(val name: String, val x: Float, val y: Float)

/** A place where loot is rolled at match start. [tier] 0 = outskirts, 1 = town, 2 = hot spot. */
class LootSpot(val x: Float, val y: Float, val tier: Int)

/** Line and circle tests used for bullets, line of sight and movement. */
object Geo {
    /** Entry time (0..1) of the segment into [r], or -1 if it never touches it. Starting inside gives 0. */
    fun segRectT(x0: Float, y0: Float, x1: Float, y1: Float, r: Rect): Float {
        var tMin = 0f; var tMax = 1f
        val dx = x1 - x0; val dy = y1 - y0
        if (abs(dx) < 1e-6f) { if (x0 < r.x || x0 > r.x2) return -1f }
        else {
            var a = (r.x - x0) / dx; var b = (r.x2 - x0) / dx; if (a > b) { val t = a; a = b; b = t }
            tMin = max(tMin, a); tMax = min(tMax, b); if (tMin > tMax) return -1f
        }
        if (abs(dy) < 1e-6f) { if (y0 < r.y || y0 > r.y2) return -1f }
        else {
            var a = (r.y - y0) / dy; var b = (r.y2 - y0) / dy; if (a > b) { val t = a; a = b; b = t }
            tMin = max(tMin, a); tMax = min(tMax, b); if (tMin > tMax) return -1f
        }
        return tMin
    }

    /** Smallest time (0..1) at which the moving point is within [rad] of (cx, cy), or -1. */
    fun segCircleT(x0: Float, y0: Float, x1: Float, y1: Float, cx: Float, cy: Float, rad: Float): Float {
        val dx = x1 - x0; val dy = y1 - y0
        val fx = x0 - cx; val fy = y0 - cy
        val c = fx * fx + fy * fy - rad * rad
        if (c <= 0f) return 0f
        val a = dx * dx + dy * dy
        if (a < 1e-9f) return -1f
        val b = 2 * (fx * dx + fy * dy)
        val disc = b * b - 4 * a * c
        if (disc < 0f) return -1f
        val t = (-b - sqrt(disc)) / (2 * a)
        return if (t in 0f..1f) t else -1f
    }

    fun dist(ax: Float, ay: Float, bx: Float, by: Float): Float { val dx = ax - bx; val dy = ay - by; return sqrt(dx * dx + dy * dy) }
}

/**
 * The arena: walls, loot spots, spawn ring and a navigation grid, all generated from [seed] alone. Host and clients
 * build the same map from the seed in the snapshot, so the layout is never sent over the wire.
 */
class BrMap(val seed: Int) {
    private companion object { const val MIN_BUILDING_W = 200f; const val MIN_BUILDING_H = 180f; const val GRID_CELL = 200f; const val LO = 0.2667f; const val HI = 0.7333f }

    val walls = ArrayList<Rect>()
    val lootSpots = ArrayList<LootSpot>()
    val pois: List<Poi> = listOf(
        Poi("Foundry", BrConst.SIZE * LO, BrConst.SIZE * LO), Poi("Depot", BrConst.SIZE * HI, BrConst.SIZE * LO), Poi("Market", BrConst.SIZE * LO, BrConst.SIZE * HI), Poi("Harbor", BrConst.SIZE * HI, BrConst.SIZE * HI), Poi("Plaza", BrConst.CENTER, BrConst.CENTER),
    )
    lateinit var spawnPoints: List<Pt>; private set
    lateinit var nav: NavGrid; private set

    // Uniform grid of wall indices so line tests, bullets and collisions only look at nearby walls.
    private val gridN = (BrConst.SIZE / GRID_CELL).toInt()
    private var grid: Array<IntArray>? = null
    private var stamp = IntArray(0); private var stampNow = 0
    private var hits = IntArray(0)

    // Must come after every property above: generation uses the grid fields.
    init { generate() }

    private fun buildGrid() {
        val lists = Array(gridN * gridN) { ArrayList<Int>() }
        walls.forEachIndexed { i, w ->
            for (cy in cellOf(w.y)..cellOf(w.y2)) for (cx in cellOf(w.x)..cellOf(w.x2)) lists[cy * gridN + cx] += i
        }
        grid = Array(lists.size) { lists[it].toIntArray() }
        stamp = IntArray(walls.size); hits = IntArray(walls.size)
    }

    private fun cellOf(v: Float) = (v / GRID_CELL).toInt().coerceIn(0, gridN - 1)

    /** Fills [hits] with the distinct walls whose grid cells overlap the box; returns how many. Not re-entrant. */
    private fun gather(minX: Float, minY: Float, maxX: Float, maxY: Float): Int {
        val g = grid
        if (g == null) { // still generating: brute force
            if (hits.size < walls.size) hits = IntArray(walls.size + 64)
            for (i in walls.indices) hits[i] = i
            return walls.size
        }
        stampNow++
        var n = 0
        for (cy in cellOf(minY)..cellOf(maxY)) for (cx in cellOf(minX)..cellOf(maxX)) for (i in g[cy * gridN + cx]) if (stamp[i] != stampNow) { stamp[i] = stampNow; hits[n++] = i }
        return n
    }

    /** True if a body of radius [r] at (x, y) overlaps no wall and is inside the map. */
    fun isFree(x: Float, y: Float, r: Float): Boolean {
        if (x < r || y < r || x > BrConst.SIZE - r || y > BrConst.SIZE - r) return false
        val rr = r * r
        val n = gather(x - r, y - r, x + r, y + r)
        for (k in 0 until n) if (walls[hits[k]].distSq(x, y) < rr) return false
        return true
    }

    /** Earliest time (0..1) a bullet moving from A to B enters a wall, or -1. */
    fun firstWallT(x0: Float, y0: Float, x1: Float, y1: Float): Float {
        var best = 2f
        val n = gather(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))
        for (k in 0 until n) { val t = Geo.segRectT(x0, y0, x1, y1, walls[hits[k]]); if (t in 0f..1f && t < best) best = t }
        return if (best > 1f) -1f else best
    }

    /** Pushes a circle out of walls and back inside the map. Writes the result to [out] (x, y). */
    fun resolve(x: Float, y: Float, r: Float, out: FloatArray) {
        var px = x; var py = y
        repeat(3) {
            val n = gather(px - r, py - r, px + r, py + r)
            for (k in 0 until n) {
                val w = walls[hits[k]]
                if (px < w.x - r || px > w.x2 + r || py < w.y - r || py > w.y2 + r) continue
                val cx = px.coerceIn(w.x, w.x2); val cy = py.coerceIn(w.y, w.y2)
                var dx = px - cx; var dy = py - cy
                val d2 = dx * dx + dy * dy
                if (d2 >= r * r) continue
                if (d2 < 1e-6f) { // centre inside the rect: leave through the nearest face
                    val l = px - w.x; val rt = w.x2 - px; val t = py - w.y; val b = w.y2 - py
                    val m = min(min(l, rt), min(t, b))
                    when (m) { l -> px = w.x - r; rt -> px = w.x2 + r; t -> py = w.y - r; else -> py = w.y2 + r }
                } else { val d = sqrt(d2); dx /= d; dy /= d; px = cx + dx * r; py = cy + dy * r }
            }
            px = px.coerceIn(r, BrConst.SIZE - r); py = py.coerceIn(r, BrConst.SIZE - r)
        }
        out[0] = px; out[1] = py
    }

    /** Clear line for a body of radius [r] from A to B. */
    fun clearLine(x0: Float, y0: Float, x1: Float, y1: Float, r: Float = 0f): Boolean {
        val n = gather(min(x0, x1) - r, min(y0, y1) - r, max(x0, x1) + r, max(y0, y1) + r)
        for (k in 0 until n) {
            val w = walls[hits[k]]
            val rect = if (r > 0f) w.inflated(r) else w
            if (Geo.segRectT(x0, y0, x1, y1, rect) >= 0f) return false
        }
        return true
    }

    /** Nearest free point to (x, y) for a body of radius [r], searching outward. */
    fun nearestFree(x: Float, y: Float, r: Float): Pt {
        if (isFree(x, y, r)) return Pt(x, y)
        var ring = 8f
        while (ring < 800f) {
            val steps = max(8, (ring / 6f).toInt())
            for (i in 0 until steps) {
                val a = i * 2 * PI.toFloat() / steps
                val px = x + cos(a) * ring; val py = y + sin(a) * ring
                if (isFree(px, py, r)) return Pt(px, py)
            }
            ring += 8f
        }
        return Pt(BrConst.CENTER, BrConst.CENTER)
    }

    private fun generate() {
        val rng = Random(seed)
        val c = BrConst.CENTER
        // Spawn ring first (rough), so cover and buildings can keep clear of it.
        val a0 = rng.nextFloat() * 2 * PI.toFloat()
        val rough = List(BrConst.FIELD) { i ->
            val a = a0 + i * 2 * PI.toFloat() / BrConst.FIELD
            Pt(c + cos(a) * (BrConst.SIZE / 2 - 100f), c + sin(a) * (BrConst.SIZE / 2 - 100f))
        }
        // Points of interest: three buildings each, one doorway per building, a few crates around.
        // Slot spacing guarantees a walkable lane (>= 90 px) between any two buildings even at maximum size and jitter,
        // so a doorway can never open onto a neighbour's wall.
        val slots = listOf(Triple(-215f, -130f, Pair(230f, 170f)), Triple(195f, -120f, Pair(200f, 160f)), Triple(-10f, 205f, Pair(240f, 170f)))
        for (poi in pois) {
            val tier = if (poi.name == "Plaza") 2 else 1
            for ((ox, oy, size) in slots) {
                val w = (size.first + rng.nextInt(-20, 21)).coerceIn(MIN_BUILDING_W, 260f); val h = (size.second + rng.nextInt(-20, 21)).coerceIn(MIN_BUILDING_H, 200f)
                val cx = poi.x + ox + rng.nextInt(-15, 16); val cy = poi.y + oy + rng.nextInt(-15, 16)
                addBuilding(Rect(cx - w / 2, cy - h / 2, w, h), rng.nextInt(4), rng)
                lootSpots += LootSpot(cx - w * 0.2f, cy, tier); lootSpots += LootSpot(cx + w * 0.2f, cy, tier)
            }
            repeat(5) {
                val a = rng.nextFloat() * 2 * PI.toFloat(); val d = 340f + rng.nextFloat() * 70f
                addCover(poi.x + cos(a) * d, poi.y + sin(a) * d, 44f, 44f, 70f)
            }
        }
        // Scattered cover and rocks.
        var placed = 0; var tries = 0
        while (placed < 64 && tries++ < 1000) {
            val w = 40f + rng.nextFloat() * 50f; val h = 40f + rng.nextFloat() * 50f
            val x = 150f + rng.nextFloat() * (BrConst.SIZE - 300f); val y = 150f + rng.nextFloat() * (BrConst.SIZE - 300f)
            if (pois.any { Geo.dist(it.x, it.y, x, y) < 310f } || rough.any { Geo.dist(it.x, it.y, x, y) < 150f }) continue
            if (addCover(x, y, w, h, 70f)) placed++
        }
        // Outskirts loot.
        tries = 0; var spots = 0
        while (spots < 44 && tries++ < 1000) {
            val x = 120f + rng.nextFloat() * (BrConst.SIZE - 240f); val y = 120f + rng.nextFloat() * (BrConst.SIZE - 240f)
            if (!isFree(x, y, 30f) || lootSpots.any { Geo.dist(it.x, it.y, x, y) < 110f }) continue
            lootSpots += LootSpot(x, y, 0); spots++
        }
        spawnPoints = rough.map { nearestFree(it.x, it.y, BrConst.BODY_R + 8f) }
        // Loot spots must be reachable and not inside walls.
        val fixed = lootSpots.map { s -> if (isFree(s.x, s.y, 12f)) s else nearestFree(s.x, s.y, 12f).let { LootSpot(it.x, it.y, s.tier) } }
        lootSpots.clear(); lootSpots += fixed
        buildGrid()
        nav = NavGrid(this)
    }

    /** Adds a wall piece; degenerate slivers (from door placement on small buildings) are skipped. */
    private fun addWall(x: Float, y: Float, w: Float, h: Float) { if (w >= 2f && h >= 2f) walls += Rect(x, y, w, h) }

    private fun addCover(x: Float, y: Float, w: Float, h: Float, margin: Float): Boolean {
        val r = Rect(x - w / 2, y - h / 2, w, h)
        if (r.x < 60f || r.y < 60f || r.x2 > BrConst.SIZE - 60f || r.y2 > BrConst.SIZE - 60f) return false
        if (walls.any { it.overlaps(r, margin) }) return false
        walls += r; return true
    }

    /** Four walls with a doorway on [doorSide] (0 top, 1 right, 2 bottom, 3 left). */
    private fun addBuilding(b: Rect, doorSide: Int, rng: Random) {
        val t = 18f; val door = 84f
        fun horizontal(y: Float, withDoor: Boolean) {
            if (!withDoor) { addWall(b.x, y, b.w, t); return }
            val dx = b.x + (b.w - door) / 2 + rng.nextInt(-20, 21)
            addWall(b.x, y, dx - b.x, t); addWall(dx + door, y, b.x2 - dx - door, t)
        }
        fun vertical(x: Float, withDoor: Boolean) {
            if (!withDoor) { addWall(x, b.y + t, t, b.h - 2 * t); return }
            val dy = b.y + (b.h - door) / 2 + rng.nextInt(-20, 21)
            addWall(x, b.y + t, t, dy - b.y - t); addWall(x, dy + door, t, b.y2 - t - dy - door)
        }
        horizontal(b.y, doorSide == 0); horizontal(b.y2 - t, doorSide == 2)
        vertical(b.x, doorSide == 3); vertical(b.x2 - t, doorSide == 1)
    }
}

/**
 * Walkability grid with A* path finding. Bots use it; humans never need it. With 20 px cells and 18 px clearance any
 * lane at least 56 px wide is visible to the grid, and the map generator keeps every lane wider than that.
 */
class NavGrid(private val map: BrMap, private val cell: Float = 20f) {
    private val n = (BrConst.SIZE / cell).toInt()
    private val blocked = BooleanArray(n * n)
    private val clearance = BrConst.BODY_R + 4f

    init {
        for (cy in 0 until n) for (cx in 0 until n) {
            val x = (cx + 0.5f) * cell; val y = (cy + 0.5f) * cell
            blocked[cy * n + cx] = !map.isFree(x, y, clearance)
        }
    }

    private fun cellOf(v: Float) = (v / cell).toInt().coerceIn(0, n - 1)
    private fun center(i: Int) = Pt((i % n + 0.5f) * cell, (i / n + 0.5f) * cell)

    fun isWalkable(x: Float, y: Float) = !blocked[cellOf(y) * n + cellOf(x)]

    private fun nearestOpen(i: Int): Int {
        if (!blocked[i]) return i
        val cx = i % n; val cy = i / n
        for (rad in 1..8) for (dy in -rad..rad) for (dx in -rad..rad) {
            if (max(abs(dx), abs(dy)) != rad) continue
            val x = cx + dx; val y = cy + dy
            if (x in 0 until n && y in 0 until n && !blocked[y * n + x]) return y * n + x
        }
        return i
    }

    private class Node(val idx: Int, val f: Float)

    /** Waypoints from (sx, sy) to (gx, gy), smoothed by line of sight, excluding the start. Null if unreachable. */
    fun path(sx: Float, sy: Float, gx: Float, gy: Float): List<Pt>? {
        val start = nearestOpen(cellOf(sy) * n + cellOf(sx)); val goal = nearestOpen(cellOf(gy) * n + cellOf(gx))
        if (blocked[start] || blocked[goal]) return null
        val g = FloatArray(n * n) { Float.MAX_VALUE }; val from = IntArray(n * n) { -1 }; val closed = BooleanArray(n * n)
        val open = PriorityQueue<Node>(compareBy { it.f })
        g[start] = 0f; open += Node(start, heuristic(start, goal))
        while (open.isNotEmpty()) {
            val cur = open.poll().idx
            if (closed[cur]) continue
            closed[cur] = true
            if (cur == goal) break
            val cx = cur % n; val cy = cur / n
            for (dy in -1..1) for (dx in -1..1) {
                if (dx == 0 && dy == 0) continue
                val x = cx + dx; val y = cy + dy
                if (x !in 0 until n || y !in 0 until n) continue
                val ni = y * n + x
                if (blocked[ni] || closed[ni]) continue
                if (dx != 0 && dy != 0 && (blocked[cy * n + x] || blocked[y * n + cx])) continue // no corner cutting
                val ng = g[cur] + if (dx != 0 && dy != 0) 1.4142f else 1f
                if (ng < g[ni]) { g[ni] = ng; from[ni] = cur; open += Node(ni, ng + heuristic(ni, goal)) }
            }
        }
        if (start != goal && from[goal] < 0) return null
        val cells = ArrayList<Int>(); var c = goal
        while (c != start) { cells += c; c = from[c] }
        cells.reverse()
        val pts = ArrayList<Pt>(cells.size + 2)
        // Start from the start cell's centre when the straight hop to it is clear, so the first leg is never a guess.
        val sc = center(start)
        if (map.clearLine(sx, sy, sc.x, sc.y, BrConst.BODY_R - 2f)) pts += sc
        for (i in cells) pts += center(i)
        // End on the real goal when it is standable and reachable in a straight hop; otherwise on the goal cell's centre.
        val last = pts.lastOrNull()
        if (map.isFree(gx, gy, BrConst.BODY_R) && (last == null || map.clearLine(last.x, last.y, gx, gy, BrConst.BODY_R - 2f))) pts += Pt(gx, gy)
        return smooth(sx, sy, pts)
    }

    private fun smooth(sx: Float, sy: Float, pts: List<Pt>): List<Pt> {
        val out = ArrayList<Pt>(); var cx = sx; var cy = sy; var i = 0
        while (i < pts.size) {
            var j = min(pts.size - 1, i + 24) // bounded lookahead keeps this cheap on long routes
            while (j > i && !map.clearLine(cx, cy, pts[j].x, pts[j].y, BrConst.BODY_R)) j--
            out += pts[j]; cx = pts[j].x; cy = pts[j].y; i = j + 1
        }
        return out
    }

    private fun heuristic(a: Int, b: Int): Float {
        val dx = abs(a % n - b % n).toFloat(); val dy = abs(a / n - b / n).toFloat()
        return (dx + dy) + (1.4142f - 2f) * min(dx, dy)
    }
}
