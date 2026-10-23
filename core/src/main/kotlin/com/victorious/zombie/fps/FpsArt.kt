package com.victorious.zombie.fps

import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.GL20
import com.badlogic.gdx.graphics.VertexAttributes.Usage
import com.badlogic.gdx.graphics.g3d.Material
import com.badlogic.gdx.graphics.g3d.Model
import com.badlogic.gdx.graphics.g3d.ModelInstance
import com.badlogic.gdx.graphics.g3d.attributes.BlendingAttribute
import com.badlogic.gdx.graphics.g3d.attributes.ColorAttribute
import com.badlogic.gdx.graphics.g3d.attributes.IntAttribute
import com.badlogic.gdx.graphics.g3d.utils.MeshPartBuilder
import com.badlogic.gdx.graphics.g3d.utils.ModelBuilder
import com.badlogic.gdx.graphics.g3d.utils.shapebuilders.BoxShapeBuilder
import com.badlogic.gdx.math.Matrix4
import com.badlogic.gdx.math.Vector3
import com.badlogic.gdx.utils.Disposable
import kotlin.math.atan2

/** A light the renderer may switch on near the player (the shader only takes a few at a time). */
class FpsLight(val x: Float, val h: Float, val z: Float, val r: Float, val g: Float, val b: Float, val intensity: Float, val needsPower: Boolean)

/**
 * Every 3D model of Zombies 3D, built from boxes and quads in code (no imported or third-party assets). Owns the GPU resources.
 * Model space: metres, +Y up, the sim's y axis is 3D z. Props and zombies face +X before rotation.
 */
class FpsArt(val map: FpsMap) : Disposable {
    private val models = ArrayList<Model>()
    private fun keep(m: Model) = m.also { models += it }
    private val pnc = (Usage.Position or Usage.Normal or Usage.ColorPacked).toLong()
    private val pn = (Usage.Position or Usage.Normal).toLong()
    private val c = Color() // declared before init {}: Kotlin runs initialisers in textual order
    private fun mat(id: String, r: Float, g: Float, b: Float, er: Float = 0f, eg: Float = 0f, eb: Float = 0f) =
        Material(id, ColorAttribute.createDiffuse(r, g, b, 1f), ColorAttribute.createEmissive(er, eg, eb, 1f))
    private fun twoSided(m: Material) = m.also { it.set(IntAttribute.createCullFace(GL20.GL_NONE)) }

    /** Static level geometry. */
    val level = ArrayList<ModelInstance>()
    val lights = ArrayList<FpsLight>()

    // shared models
    val zombie: Model
    val board: Model
    val door: Model
    val perk: Model
    val box: Model
    val beam: Model
    val power: Model
    val forge: Model
    val drop: Model
    val blood: Model
    val spark: Model
    val decal: Model
    val chalk: Model
    val knife: Model
    /** Viewmodels (with the player's hand and sleeve). */
    val guns: Array<Model>
    /** The same guns without arms, for walls and the box. */
    val gunsBare: Array<Model>

    init {
        buildLevel()
        zombie = keep(buildZombie())
        board = keep(boxModel("wood", 0.36f, 0.24f, 0.13f, 0.07f, 0.17f, 1.75f))
        door = keep(buildDoor())
        perk = keep(buildPerk())
        box = keep(buildBox())
        beam = keep(ModelBuilder().run {
            begin(); val m = Material("beam", ColorAttribute.createDiffuse(0.45f, 0.75f, 1f, 1f), ColorAttribute.createEmissive(0.35f, 0.6f, 1f, 1f), BlendingAttribute(0.22f), IntAttribute.createCullFace(GL20.GL_NONE))
            BoxShapeBuilder.build(part("beam", GL20.GL_TRIANGLES, pn, m), 0f, 4f, 0f, 0.5f, 8f, 0.5f); end()
        })
        power = keep(buildPower())
        forge = keep(buildForge())
        drop = keep(boxModel("drop", 0.2f, 0.2f, 0.2f, 0.36f, 0.36f, 0.36f, emissive = true))
        blood = keep(boxModel("p", 0.3f, 0f, 0f, 0.06f, 0.06f, 0.06f, emissive = true, er = 0.35f, eg = 0.02f, eb = 0.02f))
        spark = keep(boxModel("p", 1f, 0.8f, 0.3f, 0.04f, 0.04f, 0.04f, emissive = true, er = 1f, eg = 0.75f, eb = 0.3f))
        decal = keep(ModelBuilder().run {
            begin(); val m = Material("decal", ColorAttribute.createDiffuse(0.22f, 0.02f, 0.02f, 1f), BlendingAttribute(0.85f), IntAttribute.createCullFace(GL20.GL_NONE))
            val p = part("decal", GL20.GL_TRIANGLES, pn, m)
            p.rect(-0.55f, 0f, -0.4f, 0.5f, 0f, -0.5f, 0.45f, 0f, 0.55f, -0.5f, 0f, 0.4f, 0f, 1f, 0f); end()
        })
        chalk = keep(buildChalk())
        knife = keep(buildKnife())
        guns = Array(7) { keep(buildGun(it, true)) }
        gunsBare = Array(7) { keep(buildGun(it, false)) }
    }

    private fun boxModel(id: String, r: Float, g: Float, b: Float, w: Float, h: Float, d: Float, emissive: Boolean = false, er: Float = r, eg: Float = g, eb: Float = b) = ModelBuilder().run {
        begin(); BoxShapeBuilder.build(part(id, GL20.GL_TRIANGLES, pn, if (emissive) mat(id, r, g, b, er, eg, eb) else mat(id, r, g, b)), 0f, 0f, 0f, w, h, d); end()
    }

    // ---- level ------------------------------------------------------------------------------------------------------
    private fun hash(x: Int, y: Int, k: Int): Float { var h = x * 374761393 + y * 668265263 + k * 1442695041; h = (h xor (h ushr 13)) * 1274126177; return ((h xor (h ushr 16)) and 0xFFFF) / 65535f }
    private fun col(p: MeshPartBuilder, r: Float, g: Float, b: Float, v: Float) { c.set((r * v).coerceIn(0f, 1f), (g * v).coerceIn(0f, 1f), (b * v).coerceIn(0f, 1f), 1f); p.setColor(c) }

    /** A vertical quad from (ax,az) to (bx,bz) between heights y0 and y1, split into [hs] x [vs] cells for smoother vertex lighting. */
    private fun wallQuad(p: MeshPartBuilder, ax: Float, az: Float, bx: Float, bz: Float, y0: Float, y1: Float, nx: Float, nz: Float, hs: Int, vs: Int, outside: Boolean, seed: Int) {
        for (i in 0 until hs) for (j in 0 until vs) {
            val u0 = i.toFloat() / hs; val u1 = (i + 1f) / hs
            val ya = y0 + (y1 - y0) * j / vs; val yb = y0 + (y1 - y0) * (j + 1) / vs
            val v = 0.82f + 0.3f * hash(seed, i, j)
            val grime = if (ya < 0.7f) 0.7f else if (yb > FpsMap.WALL_H - 0.4f) 0.85f else 1f
            if (outside) col(p, 0.27f, 0.27f, 0.26f, v * grime) else col(p, 0.36f, 0.29f, 0.25f, v * grime)
            p.rect(ax + (bx - ax) * u0, ya, az + (bz - az) * u0, ax + (bx - ax) * u1, ya, az + (bz - az) * u1,
                ax + (bx - ax) * u1, yb, az + (bz - az) * u1, ax + (bx - ax) * u0, yb, az + (bz - az) * u0, nx, 0f, nz)
        }
    }

    private fun buildLevel() {
        val C = FpsMap.CELL; val H = FpsMap.WALL_H
        val mb = ModelBuilder()
        // floors and ceilings
        mb.begin()
        val fl = mb.part("floor", GL20.GL_TRIANGLES, pnc, twoSided(Material("floor", ColorAttribute.createDiffuse(Color.WHITE))))
        val ce = mb.part("ceil", GL20.GL_TRIANGLES, pnc, twoSided(Material("ceil", ColorAttribute.createDiffuse(Color.WHITE))))
        val tint = arrayOf(floatArrayOf(1f, 1f, 1f), floatArrayOf(0.92f, 0.95f, 1.05f), floatArrayOf(1.06f, 0.98f, 0.9f), floatArrayOf(0.95f, 1.04f, 0.92f))
        for (ty in 0 until map.h) for (tx in 0 until map.w) {
            val t = map.at(tx, ty)
            if (t != Tile.FLOOR && t != Tile.DOOR && t != Tile.OBJECT) continue
            val tn = tint[map.zoneAt(tx, ty).coerceAtLeast(0) % tint.size]
            for (i in 0..1) for (j in 0..1) {
                val x0 = tx * C + i * C / 2; val z0 = ty * C + j * C / 2; val x1 = x0 + C / 2; val z1 = z0 + C / 2
                val v = 0.75f + 0.35f * hash(tx * 2 + i, ty * 2 + j, 1) * (if ((tx + ty) % 2 == 0) 1f else 0.9f)
                col(fl, 0.31f * tn[0], 0.3f * tn[1], 0.28f * tn[2], v)
                fl.rect(x0, 0f, z1, x1, 0f, z1, x1, 0f, z0, x0, 0f, z0, 0f, 1f, 0f)
                col(ce, 0.15f, 0.145f, 0.14f, 0.8f + 0.3f * hash(tx, ty, 2))
                ce.rect(x0, H, z0, x1, H, z0, x1, H, z1, x0, H, z1, 0f, -1f, 0f)
            }
        }
        level += ModelInstance(keep(mb.end()))
        // outside ground
        mb.begin()
        val og = mb.part("ground", GL20.GL_TRIANGLES, pnc, twoSided(Material("ground", ColorAttribute.createDiffuse(Color.WHITE))))
        for (ty in 0 until map.h) for (tx in 0 until map.w) {
            if (map.at(tx, ty) != Tile.OUTSIDE) continue
            col(og, 0.13f, 0.14f, 0.1f, 0.7f + 0.5f * hash(tx, ty, 3))
            og.rect(tx * C, 0f, (ty + 1) * C, (tx + 1) * C, 0f, (ty + 1) * C, (tx + 1) * C, 0f, ty * C, tx * C, 0f, ty * C, 0f, 1f, 0f)
        }
        level += ModelInstance(keep(mb.end()))
        // walls, window openings and door lintels
        mb.begin()
        val wl = mb.part("wall", GL20.GL_TRIANGLES, pnc, twoSided(Material("wall", ColorAttribute.createDiffuse(Color.WHITE))))
        val dxs = intArrayOf(1, -1, 0, 0); val dys = intArrayOf(0, 0, 1, -1)
        for (ty in 0 until map.h) for (tx in 0 until map.w) {
            val t = map.at(tx, ty)
            if (t != Tile.WALL && t != Tile.WINDOW && t != Tile.DOOR) continue
            for (k in 0 until 4) {
                val nt = map.at(tx + dxs[k], ty + dys[k])
                if (nt == Tile.WALL || nt == Tile.VOID || nt == Tile.WINDOW) continue
                if (t == Tile.DOOR && nt != Tile.FLOOR && nt != Tile.OBJECT) continue
                // the face on the boundary toward the neighbour, from A to B
                val (ax, az, bx, bz) = when (k) {
                    0 -> floatArrayOf((tx + 1) * C, ty * C, (tx + 1) * C, (ty + 1) * C)
                    1 -> floatArrayOf(tx * C, (ty + 1) * C, tx * C, ty * C)
                    2 -> floatArrayOf((tx + 1) * C, (ty + 1) * C, tx * C, (ty + 1) * C)
                    else -> floatArrayOf(tx * C, ty * C, (tx + 1) * C, ty * C)
                }.let { arrayOf(it[0], it[1], it[2], it[3]) }
                val nx = dxs[k].toFloat(); val nz = dys[k].toFloat()
                val out = nt == Tile.OUTSIDE
                val seed = (ty * map.w + tx) * 4 + k
                when (t) {
                    Tile.WALL -> wallQuad(wl, ax, az, bx, bz, 0f, H, nx, nz, 2, 3, out, seed)
                    Tile.DOOR -> wallQuad(wl, ax, az, bx, bz, DOOR_H, H, nx, nz, 2, 1, false, seed)
                    Tile.WINDOW -> { // wall around a hole
                        fun at(u: Float) = floatArrayOf(ax + (bx - ax) * u, az + (bz - az) * u)
                        val l = at(HOLE_U0); val r = at(HOLE_U1)
                        wallQuad(wl, ax, az, bx, bz, 0f, SILL, nx, nz, 2, 1, out, seed)
                        wallQuad(wl, ax, az, bx, bz, LINTEL, H, nx, nz, 2, 1, out, seed + 1)
                        wallQuad(wl, ax, az, l[0], l[1], SILL, LINTEL, nx, nz, 1, 2, out, seed + 2)
                        wallQuad(wl, r[0], r[1], bx, bz, SILL, LINTEL, nx, nz, 1, 2, out, seed + 3)
                    }
                    else -> {}
                }
            }
            if (t == Tile.WINDOW) windowReveal(wl, tx, ty)
            if (t == Tile.DOOR) { col(wl, 0.3f, 0.26f, 0.23f, 0.8f); wl.rect(tx * C, DOOR_H, ty * C, (tx + 1) * C, DOOR_H, ty * C, (tx + 1) * C, DOOR_H, (ty + 1) * C, tx * C, DOOR_H, (ty + 1) * C, 0f, -1f, 0f) }
        }
        level += ModelInstance(keep(mb.end()))
        buildLamps()
    }

    /** The inside of a window hole: sill, lintel and the two jambs, through the thickness of the wall tile. */
    private fun windowReveal(p: MeshPartBuilder, tx: Int, ty: Int) {
        val C = FpsMap.CELL
        val w = map.windowAt(tx, ty)!!
        val alongX = w.inY != ty // the hole runs along z when the inside is north/south of it... compute both ways below
        val x0 = tx * C; val z0 = ty * C
        col(p, 0.33f, 0.28f, 0.24f, 0.75f)
        if (alongX) { // passage along z: the hole spans x
            val a = x0 + HOLE_U0 * C; val b = x0 + HOLE_U1 * C
            p.rect(a, SILL, z0, b, SILL, z0, b, SILL, z0 + C, a, SILL, z0 + C, 0f, 1f, 0f)
            p.rect(a, LINTEL, z0 + C, b, LINTEL, z0 + C, b, LINTEL, z0, a, LINTEL, z0, 0f, -1f, 0f)
            p.rect(a, SILL, z0 + C, a, SILL, z0, a, LINTEL, z0, a, LINTEL, z0 + C, 1f, 0f, 0f)
            p.rect(b, SILL, z0, b, SILL, z0 + C, b, LINTEL, z0 + C, b, LINTEL, z0, -1f, 0f, 0f)
        } else {
            val a = z0 + HOLE_U0 * C; val b = z0 + HOLE_U1 * C
            p.rect(x0, SILL, a, x0 + C, SILL, a, x0 + C, SILL, b, x0, SILL, b, 0f, 1f, 0f)
            p.rect(x0, LINTEL, b, x0 + C, LINTEL, b, x0 + C, LINTEL, a, x0, LINTEL, a, 0f, -1f, 0f)
            p.rect(x0, SILL, a, x0 + C, SILL, a, x0 + C, LINTEL, a, x0, LINTEL, a, 0f, 0f, 1f)
            p.rect(x0 + C, SILL, b, x0, SILL, b, x0, LINTEL, b, x0 + C, LINTEL, b, 0f, 0f, -1f)
        }
    }

    /** Bare bulbs hanging from the ceiling, about one per 30 m2 of room, plus a cold light over every window. */
    private fun buildLamps() {
        val C = FpsMap.CELL
        val bulb = keep(ModelBuilder().run {
            begin()
            BoxShapeBuilder.build(part("cord", GL20.GL_TRIANGLES, pn, mat("cord", 0.05f, 0.05f, 0.05f)), 0f, 0.25f, 0f, 0.02f, 0.5f, 0.02f)
            BoxShapeBuilder.build(part("bulb", GL20.GL_TRIANGLES, pn, mat("bulb", 1f, 0.85f, 0.55f, 1f, 0.8f, 0.45f)), 0f, -0.05f, 0f, 0.12f, 0.16f, 0.12f)
            end()
        })
        for (zn in 0 until map.zoneCount) {
            val tiles = ArrayList<Pair<Int, Int>>()
            for (ty in 0 until map.h) for (tx in 0 until map.w) if (map.at(tx, ty) == Tile.FLOOR && map.zoneAt(tx, ty) == zn) tiles += tx to ty
            if (tiles.isEmpty()) continue
            val n = (tiles.size / 8).coerceIn(1, 4)
            // spread the bulbs: farthest-point picks starting from the room centre
            val cx = tiles.map { it.first }.average(); val cy = tiles.map { it.second }.average()
            val picks = ArrayList<Pair<Int, Int>>()
            picks += tiles.minBy { (it.first - cx) * (it.first - cx) + (it.second - cy) * (it.second - cy) }
            while (picks.size < n) picks += tiles.maxBy { t -> picks.minOf { (it.first - t.first) * (it.first - t.first) + (it.second - t.second) * (it.second - t.second) } }
            for ((tx, ty) in picks) {
                val x = (tx + 0.5f) * C; val z = (ty + 0.5f) * C
                level += ModelInstance(bulb, x, FpsMap.WALL_H - 0.55f, z)
                lights += FpsLight(x, FpsMap.WALL_H - 0.7f, z, 1f, 0.72f, 0.42f, 4.2f, false)
            }
        }
        for (w in map.windows) lights += FpsLight((w.outX + 0.5f) * C, 2.6f, (w.outY + 0.5f) * C, 0.35f, 0.45f, 0.7f, 2.5f, false)
    }

    // ---- characters ---------------------------------------------------------------------------------------------------
    private fun buildZombie(): Model {
        val mb = ModelBuilder(); mb.begin()
        val skin = mat("skin", 0.45f, 0.5f, 0.4f); val shirt = mat("shirt", 0.24f, 0.22f, 0.18f); val pants = mat("pants", 0.15f, 0.15f, 0.16f)
        val eyes = mat("eyes", 1f, 0.75f, 0.1f, 1f, 0.7f, 0.08f)
        fun node(id: String, x: Float, y: Float, z: Float) { val n = mb.node(); n.id = id; n.translation.set(x, y, z) }
        node("legL", 0f, 0.85f, -0.11f); BoxShapeBuilder.build(mb.part("legL", GL20.GL_TRIANGLES, pn, pants), 0f, -0.4f, 0f, 0.17f, 0.82f, 0.16f)
        node("legR", 0f, 0.85f, 0.11f); BoxShapeBuilder.build(mb.part("legR", GL20.GL_TRIANGLES, pn, pants), 0f, -0.4f, 0f, 0.17f, 0.82f, 0.16f)
        node("torso", 0f, 0.85f, 0f)
        BoxShapeBuilder.build(mb.part("torso", GL20.GL_TRIANGLES, pn, shirt), 0f, 0.31f, 0f, 0.27f, 0.64f, 0.44f)
        BoxShapeBuilder.build(mb.part("neck", GL20.GL_TRIANGLES, pn, skin), 0f, 0.66f, 0f, 0.11f, 0.08f, 0.11f)
        node("head", 0.02f, 1.47f, 0f)
        BoxShapeBuilder.build(mb.part("head", GL20.GL_TRIANGLES, pn, skin), 0.02f, 0.15f, 0f, 0.25f, 0.27f, 0.22f)
        BoxShapeBuilder.build(mb.part("jaw", GL20.GL_TRIANGLES, pn, mat("jaw", 0.25f, 0.12f, 0.1f)), 0.13f, 0.06f, 0f, 0.03f, 0.05f, 0.12f)
        BoxShapeBuilder.build(mb.part("eyeL", GL20.GL_TRIANGLES, pn, eyes), 0.14f, 0.18f, -0.055f, 0.02f, 0.035f, 0.05f)
        BoxShapeBuilder.build(mb.part("eyeR", GL20.GL_TRIANGLES, pn, eyes), 0.14f, 0.18f, 0.055f, 0.02f, 0.035f, 0.05f)
        node("armL", 0f, 1.42f, -0.28f)
        BoxShapeBuilder.build(mb.part("sleeveL", GL20.GL_TRIANGLES, pn, shirt), 0f, -0.15f, 0f, 0.13f, 0.3f, 0.13f)
        BoxShapeBuilder.build(mb.part("handL", GL20.GL_TRIANGLES, pn, skin), 0f, -0.45f, 0f, 0.11f, 0.32f, 0.11f)
        node("armR", 0f, 1.42f, 0.28f)
        BoxShapeBuilder.build(mb.part("sleeveR", GL20.GL_TRIANGLES, pn, shirt), 0f, -0.15f, 0f, 0.13f, 0.3f, 0.13f)
        BoxShapeBuilder.build(mb.part("handR", GL20.GL_TRIANGLES, pn, skin), 0f, -0.45f, 0f, 0.11f, 0.32f, 0.11f)
        return mb.end()
    }

    /** Guns are built pointing down -Z with the grip near the origin, ready to sit in front of the camera. */
    private fun buildGun(shape: Int, arm: Boolean): Model {
        val mb = ModelBuilder(); mb.begin()
        val metal = mat("metal", 0.17f, 0.17f, 0.19f); val wood = mat("wood", 0.34f, 0.2f, 0.1f)
        val glow = mat("glow", 0.3f, 0.9f, 1f, 0.3f, 0.85f, 1f); val sleeve = mat("sleeve", 0.16f, 0.2f, 0.12f); val hand = mat("hand", 0.55f, 0.42f, 0.33f)
        fun b(m: Material, id: String, x: Float, y: Float, z: Float, w: Float, h: Float, d: Float) = BoxShapeBuilder.build(mb.part(id, GL20.GL_TRIANGLES, pn, m), x, y, z, w, h, d)
        if (arm) b(hand, "hand", 0f, -0.07f, 0.05f, 0.07f, 0.07f, 0.09f)
        if (arm) b(sleeve, "arm", 0.04f, -0.12f, 0.17f, 0.09f, 0.09f, 0.2f)
        when (shape) {
            0 -> { b(metal, "slide", 0f, 0f, -0.04f, 0.035f, 0.045f, 0.2f); b(metal, "grip", 0f, -0.06f, 0.03f, 0.032f, 0.1f, 0.045f) }
            1 -> { b(wood, "stock", 0f, -0.02f, 0.2f, 0.045f, 0.08f, 0.22f); b(metal, "body", 0f, 0f, -0.05f, 0.05f, 0.07f, 0.32f); b(metal, "barrel", 0f, 0.01f, -0.35f, 0.022f, 0.022f, 0.32f); b(metal, "mag", 0f, -0.08f, -0.06f, 0.03f, 0.1f, 0.05f); b(wood, "fore", 0f, -0.02f, -0.22f, 0.05f, 0.04f, 0.18f) }
            2 -> { b(wood, "stock", 0f, -0.03f, 0.2f, 0.05f, 0.09f, 0.24f); b(metal, "body", 0f, 0f, -0.02f, 0.055f, 0.07f, 0.22f); b(metal, "barrel", 0f, 0.015f, -0.33f, 0.04f, 0.04f, 0.42f); b(wood, "pump", 0f, -0.03f, -0.26f, 0.055f, 0.045f, 0.16f) }
            3 -> { b(metal, "body", 0f, 0f, -0.04f, 0.05f, 0.075f, 0.28f); b(metal, "barrel", 0f, 0.01f, -0.24f, 0.025f, 0.025f, 0.14f); b(metal, "mag", 0f, -0.12f, -0.08f, 0.03f, 0.17f, 0.045f); b(metal, "stock", 0f, 0f, 0.17f, 0.02f, 0.05f, 0.16f) }
            4 -> { b(metal, "body", 0f, 0.01f, -0.06f, 0.07f, 0.09f, 0.4f); b(metal, "barrel", 0f, 0.02f, -0.42f, 0.03f, 0.03f, 0.36f); b(metal, "drum", 0.05f, -0.08f, -0.06f, 0.08f, 0.12f, 0.12f); b(wood, "stock", 0f, -0.02f, 0.2f, 0.05f, 0.09f, 0.2f) }
            5 -> { b(wood, "stock", 0f, -0.03f, 0.2f, 0.05f, 0.09f, 0.24f); b(metal, "body", 0f, 0f, -0.05f, 0.05f, 0.07f, 0.34f); b(metal, "barrel", 0f, 0.01f, -0.45f, 0.024f, 0.024f, 0.5f); b(metal, "scope", 0f, 0.075f, -0.06f, 0.045f, 0.045f, 0.26f); b(glow, "lens", 0f, 0.075f, -0.195f, 0.04f, 0.04f, 0.005f) }
            else -> { b(metal, "body", 0f, 0f, -0.06f, 0.08f, 0.1f, 0.3f); b(glow, "coil1", 0f, 0f, -0.26f, 0.1f, 0.1f, 0.03f); b(glow, "coil2", 0f, 0f, -0.33f, 0.09f, 0.09f, 0.03f); b(glow, "coil3", 0f, 0f, -0.4f, 0.08f, 0.08f, 0.03f); b(metal, "rod", 0f, 0f, -0.33f, 0.03f, 0.03f, 0.22f) }
        }
        return mb.end()
    }

    private fun buildKnife(): Model {
        val mb = ModelBuilder(); mb.begin()
        BoxShapeBuilder.build(mb.part("blade", GL20.GL_TRIANGLES, pn, mat("blade", 0.7f, 0.72f, 0.75f, 0.12f, 0.12f, 0.13f)), 0f, 0f, -0.14f, 0.008f, 0.035f, 0.2f)
        BoxShapeBuilder.build(mb.part("handle", GL20.GL_TRIANGLES, pn, mat("handle", 0.12f, 0.08f, 0.06f)), 0f, 0f, 0.0f, 0.03f, 0.04f, 0.1f)
        BoxShapeBuilder.build(mb.part("arm", GL20.GL_TRIANGLES, pn, mat("sleeve", 0.16f, 0.2f, 0.12f)), 0f, -0.03f, 0.15f, 0.09f, 0.09f, 0.2f)
        return mb.end()
    }

    // ---- props ------------------------------------------------------------------------------------------------------
    private fun buildDoor(): Model {
        val mb = ModelBuilder(); mb.begin()
        val rust = mat("rust", 0.3f, 0.2f, 0.14f); val wood = mat("wood", 0.33f, 0.22f, 0.12f)
        BoxShapeBuilder.build(mb.part("panel", GL20.GL_TRIANGLES, pn, rust), 0f, DOOR_H / 2, 0f, 0.18f, DOOR_H, 1.98f)
        for (i in 0 until 3) BoxShapeBuilder.build(mb.part("plank$i", GL20.GL_TRIANGLES, pn, wood), 0.13f, 0.6f + i * 0.7f, 0f, 0.06f, 0.18f, 1.9f)
        return mb.end()
    }

    private fun buildPerk(): Model {
        val mb = ModelBuilder(); mb.begin()
        BoxShapeBuilder.build(mb.part("body", GL20.GL_TRIANGLES, pn, mat("body", 0.2f, 0.2f, 0.2f)), 0f, 1f, 0f, 0.75f, 2f, 0.95f)
        BoxShapeBuilder.build(mb.part("sign", GL20.GL_TRIANGLES, pn, mat("sign", 0.3f, 0.3f, 0.3f)), 0.02f, 1.86f, 0f, 0.77f, 0.3f, 0.97f)
        BoxShapeBuilder.build(mb.part("glass", GL20.GL_TRIANGLES, pn, mat("glass", 0.1f, 0.1f, 0.1f)), 0.38f, 1.15f, 0f, 0.02f, 0.9f, 0.7f)
        BoxShapeBuilder.build(mb.part("slot", GL20.GL_TRIANGLES, pn, mat("slot", 0.05f, 0.05f, 0.05f)), 0.38f, 0.45f, 0f, 0.04f, 0.18f, 0.4f)
        return mb.end()
    }

    private fun buildBox(): Model {
        val mb = ModelBuilder(); mb.begin()
        val wood = mat("crate", 0.36f, 0.25f, 0.13f); val trim = mat("trim", 0.22f, 0.18f, 0.1f); val mark = mat("mark", 0.6f, 0.75f, 1f, 0.45f, 0.65f, 1f)
        BoxShapeBuilder.build(mb.part("crate", GL20.GL_TRIANGLES, pn, wood), 0f, 0.4f, 0f, 0.85f, 0.8f, 1.75f)
        BoxShapeBuilder.build(mb.part("lid", GL20.GL_TRIANGLES, pn, trim), 0f, 0.82f, 0f, 0.9f, 0.06f, 1.8f)
        for (z in listOf(-0.6f, 0f, 0.6f)) BoxShapeBuilder.build(mb.part("q$z", GL20.GL_TRIANGLES, pn, mark), 0.43f, 0.45f, z, 0.01f, 0.25f, 0.16f)
        return mb.end()
    }

    private fun buildPower(): Model {
        val mb = ModelBuilder(); mb.begin()
        BoxShapeBuilder.build(mb.part("box", GL20.GL_TRIANGLES, pn, mat("box", 0.25f, 0.27f, 0.22f)), 0f, 0.9f, 0f, 0.45f, 1.8f, 0.9f)
        val n = mb.node(); n.id = "lever"; n.translation.set(0.25f, 1.1f, 0f)
        BoxShapeBuilder.build(mb.part("lever", GL20.GL_TRIANGLES, pn, mat("lever", 0.6f, 0.1f, 0.08f)), 0.06f, 0.2f, 0f, 0.05f, 0.4f, 0.05f)
        val l = mb.node(); l.id = "lamp"; l.translation.set(0.23f, 1.6f, 0f)
        BoxShapeBuilder.build(mb.part("lamp", GL20.GL_TRIANGLES, pn, mat("lamp", 0.8f, 0.1f, 0.1f, 0.8f, 0.05f, 0.05f)), 0f, 0f, 0f, 0.04f, 0.1f, 0.1f)
        return mb.end()
    }

    private fun buildForge(): Model {
        val mb = ModelBuilder(); mb.begin()
        val iron = mat("iron", 0.16f, 0.15f, 0.17f)
        BoxShapeBuilder.build(mb.part("base", GL20.GL_TRIANGLES, pn, iron), 0f, 0.45f, 0f, 1.4f, 0.9f, 1.4f)
        BoxShapeBuilder.build(mb.part("top", GL20.GL_TRIANGLES, pn, iron), 0f, 2.0f, 0f, 1.2f, 0.4f, 1.2f)
        for ((x, z) in listOf(-0.5f to -0.5f, 0.5f to -0.5f, -0.5f to 0.5f, 0.5f to 0.5f)) BoxShapeBuilder.build(mb.part("post", GL20.GL_TRIANGLES, pn, iron), x, 1.35f, z, 0.12f, 0.9f, 0.12f)
        BoxShapeBuilder.build(mb.part("core", GL20.GL_TRIANGLES, pn, mat("core", 0.3f, 0.1f, 0.35f)), 0f, 1.35f, 0f, 0.5f, 0.5f, 0.5f)
        return mb.end()
    }

    private fun buildChalk(): Model {
        val mb = ModelBuilder(); mb.begin()
        val m = mat("chalk", 0.85f, 0.83f, 0.7f, 0.45f, 0.44f, 0.36f)
        // a rough rectangle outline in the wall plane (x = wall normal), 1.3 wide and 0.6 tall
        for ((y, h) in listOf(0.3f to 0.03f, -0.3f to 0.03f)) BoxShapeBuilder.build(mb.part("h$y", GL20.GL_TRIANGLES, pn, m), 0f, y, 0f, 0.005f, h, 1.3f)
        for (z in listOf(-0.65f, 0.65f)) BoxShapeBuilder.build(mb.part("v$z", GL20.GL_TRIANGLES, pn, m), 0f, 0f, z, 0.005f, 0.63f, 0.03f)
        return mb.end()
    }

    override fun dispose() { models.forEach { it.dispose() }; models.clear() }

    companion object {
        const val SILL = 0.8f; const val LINTEL = 2.35f; const val HOLE_U0 = 0.15f; const val HOLE_U1 = 0.85f
        const val DOOR_H = 2.5f

        /** Rotation (degrees about +Y) that turns a model facing +X toward the sim direction (fx, fy). */
        fun yawDeg(fx: Float, fy: Float) = -Math.toDegrees(atan2(fy, fx).toDouble()).toFloat()

        /** World transform for a gun hung on a wall: barrel along the wall, lying flat against it, facing out along (fx, fy). */
        fun wallGun(out: Matrix4, x: Float, y: Float, z: Float, fx: Float, fy: Float, scale: Float): Matrix4 {
            val zAxis = Vector3(-fy, 0f, fx) // local Z runs along the wall (right-handed with X out of the wall and Y up)
            val xAxis = Vector3(fx, 0f, fy)
            val yAxis = Vector3(zAxis).crs(xAxis).nor()
            return out.set(xAxis, yAxis, zAxis, Vector3(x, y, z)).scale(scale, scale, scale)
        }
    }
}
