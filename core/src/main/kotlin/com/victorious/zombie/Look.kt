package com.victorious.zombie

import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.GL20
import com.badlogic.gdx.graphics.Pixmap
import com.badlogic.gdx.graphics.Texture
import com.badlogic.gdx.graphics.g2d.BitmapFont
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.badlogic.gdx.graphics.g2d.TextureRegion
import com.badlogic.gdx.utils.Disposable
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Procedural art and effects for the gritty, dark survival-horror look (see docs/VISUAL_DIRECTION.md). Everything is generated
 * at start-up from code: no image files, nothing copied from other games. Needs a GL context; create it inside a screen.
 */
class Look : Disposable {
    private val rnd = Random(20)
    private val textures = ArrayList<Texture>()

    /** Soft round light/glow, white with a radial alpha falloff. Tint it with the batch colour. */
    val glow: Texture
    /** Screen-edge darkening: transparent in the middle, opaque toward the corners. Tint black or red. */
    val vignette: Texture
    /** Seamless concrete tile; repeats. */
    val floor: Texture
    private val splats: List<TextureRegion>
    val zombieSprites: List<TextureRegion>
    val soldier: TextureRegion

    init {
        glow = tex(radial(128) { d -> (1f - d).coerceIn(0f, 1f).pow(2.2f) }, mip = false)
        vignette = tex(vignetteMap(128), mip = false)
        floor = tex(concrete(128), mip = true).also { it.setWrap(Texture.TextureWrap.Repeat, Texture.TextureWrap.Repeat) }
        // Every texture is a power of two: OpenGL ES 2.0 (the Android default) cannot mipmap or repeat non-power-of-two textures.
        splats = List(4) { TextureRegion(tex(splat(128, it), mip = true)) }
        zombieSprites = listOf(Color(0.52f, 0.66f, 0.42f, 1f), Color(0.66f, 0.64f, 0.48f, 1f), Color(0.46f, 0.60f, 0.58f, 1f)).mapIndexed { i, c -> TextureRegion(tex(zombie(64, c, i), mip = true)) }
        soldier = TextureRegion(tex(soldier(64), mip = true))
    }

    private fun tex(pm: Pixmap, mip: Boolean): Texture {
        val t = Texture(pm, mip)
        t.setFilter(if (mip) Texture.TextureFilter.MipMapLinearLinear else Texture.TextureFilter.Linear, Texture.TextureFilter.Linear)
        pm.dispose(); textures += t
        return t
    }

    // ---- generated art ----------------------------------------------------------------------------------------------
    private fun radial(size: Int, alphaAt: (Float) -> Float): Pixmap {
        val pm = Pixmap(size, size, Pixmap.Format.RGBA8888)
        val c = (size - 1) / 2f
        for (y in 0 until size) for (x in 0 until size) {
            val d = hypot(x - c, y - c) / c
            pm.drawPixel(x, y, Color.rgba8888(1f, 1f, 1f, alphaAt(d)))
        }
        return pm
    }

    private fun vignetteMap(size: Int): Pixmap {
        val pm = Pixmap(size, size, Pixmap.Format.RGBA8888)
        val c = (size - 1) / 2f
        for (y in 0 until size) for (x in 0 until size) {
            val d = hypot((x - c) / c, (y - c) / c) / 1.4142f
            val t = ((d - 0.38f) / 0.62f).coerceIn(0f, 1f)
            pm.drawPixel(x, y, Color.rgba8888(1f, 1f, 1f, t * t * (3 - 2 * t) * 0.95f))
        }
        return pm
    }

    private fun concrete(size: Int): Pixmap {
        val pm = Pixmap(size, size, Pixmap.Format.RGBA8888)
        for (y in 0 until size) for (x in 0 until size) {
            val n = (rnd.nextFloat() - 0.5f) * 0.045f
            val blotch = (sin(x * 0.11f) * sin(y * 0.09f)) * 0.012f
            val g = 0.135f + n + blotch
            pm.drawPixel(x, y, Color.rgba8888(g, g * 0.98f, g * 1.04f, 1f))
        }
        // slab seams and a few cracks (wrapping so the tile stays seamless)
        for (i in 0 until size) { pm.drawPixel(i, 0, Color.rgba8888(0.112f, 0.11f, 0.118f, 1f)); pm.drawPixel(0, i, Color.rgba8888(0.112f, 0.11f, 0.118f, 1f)) }
        repeat(3) {
            var x = rnd.nextInt(size).toFloat(); var y = rnd.nextInt(size).toFloat(); var a = rnd.nextFloat() * 2 * PI.toFloat()
            repeat(14 + rnd.nextInt(18)) {
                pm.drawPixel(((x % size) + size).toInt() % size, ((y % size) + size).toInt() % size, Color.rgba8888(0.085f, 0.085f, 0.09f, 1f))
                a += (rnd.nextFloat() - 0.5f) * 0.9f; x += cos(a); y += sin(a)
            }
        }
        return pm
    }

    private fun splat(size: Int, seed: Int): Pixmap {
        val r = Random(seed * 31 + 5)
        val pm = Pixmap(size, size, Pixmap.Format.RGBA8888)
        val c = size / 2f
        val k = size / 96f // the shapes below were drawn for a 96 px canvas
        fun disc(x: Float, y: Float, rad: Float, shade: Float) {
            pm.setColor(0.42f * shade, 0.02f * shade, 0.03f * shade, 0.92f)
            pm.fillCircle(x.toInt(), y.toInt(), max(1, (rad * k).toInt()))
        }
        disc(c, c, 13f + r.nextFloat() * 5f, 1f)
        repeat(9 + r.nextInt(6)) {
            val a = r.nextFloat() * 2 * PI.toFloat(); val d = 8f + r.nextFloat() * 28f
            disc(c + cos(a) * d * k, c + sin(a) * d * k, 2f + r.nextFloat() * (8f - d / 8f), 0.8f + r.nextFloat() * 0.3f)
        }
        repeat(14) { val a = r.nextFloat() * 2 * PI.toFloat(); val d = 20f + r.nextFloat() * 24f; disc(c + cos(a) * d * k, c + sin(a) * d * k, 1f + r.nextFloat() * 1.5f, 0.9f) }
        disc(c, c, 7f, 0.55f) // darker, wetter middle
        return pm
    }

    private fun Pixmap.ellipse(cx: Float, cy: Float, rx: Float, ry: Float, c: Color) {
        setColor(c)
        var y = -ry
        while (y <= ry) { val hw = rx * sqrt(max(0f, 1f - (y / ry) * (y / ry))); fillRectangle((cx - hw).toInt(), (cy + y).toInt(), max(1, (hw * 2).toInt()), 1); y += 1f }
    }

    private fun Pixmap.thick(x0: Float, y0: Float, x1: Float, y1: Float, w: Float, c: Color) {
        setColor(c)
        val n = max(1, hypot(x1 - x0, y1 - y0).toInt())
        for (i in 0..n) { val t = i / n.toFloat(); fillCircle((x0 + (x1 - x0) * t).toInt(), (y0 + (y1 - y0) * t).toInt(), max(1, (w / 2).toInt())) }
    }

    private fun shade(c: Color, k: Float) = Color(c.r * k, c.g * k, c.b * k, 1f)

    /** A shambling top-down zombie facing +x: ragged shoulders, head, reaching arms, dim glowing eyes. */
    private fun zombie(size: Int, skin: Color, variant: Int): Pixmap {
        val pm = Pixmap(size, size, Pixmap.Format.RGBA8888)
        val r = Random(variant * 17 + 3)
        val cloth = Color(0.22f + variant * 0.03f, 0.20f, 0.17f, 1f)
        val cy = size / 2f
        pm.ellipse(24f, cy, 11f, 19f, shade(cloth, 0.55f)) // outline
        pm.ellipse(24f, cy, 9.5f, 17.5f, cloth)
        repeat(6) { // rips and stains on the clothes
            pm.setColor(0.28f, 0.03f, 0.04f, 0.85f); pm.fillCircle(16 + r.nextInt(14), (cy - 12 + r.nextInt(24)).toInt(), 2 + r.nextInt(3))
        }
        for (s in listOf(-1f, 1f)) { // reaching arms with grasping hands
            pm.thick(26f, cy + s * 14f, 49f, cy + s * 8f - s * 2f, 6.5f, shade(skin, 0.55f))
            pm.thick(26f, cy + s * 14f, 49f, cy + s * 8f - s * 2f, 4.5f, skin)
            pm.setColor(shade(skin, 0.7f)); pm.fillCircle(52, (cy + s * 6f).toInt(), 4)
        }
        pm.setColor(shade(skin, 0.5f)); pm.fillCircle(31, cy.toInt(), 11) // head rim
        pm.setColor(skin); pm.fillCircle(31, cy.toInt(), 9)
        pm.setColor(0.13f, 0.11f, 0.09f, 1f); pm.fillCircle(26, cy.toInt(), 5) // matted hair at the back of the head
        pm.setColor(0.35f, 0.04f, 0.05f, 0.9f); pm.fillCircle(33, (cy + 5).toInt(), 3) // wound
        for (s in listOf(-1f, 1f)) { // eyes: dim amber glow
            pm.setColor(1f, 0.62f, 0.12f, 0.35f); pm.fillCircle(38, (cy + s * 4f).toInt(), 4)
            pm.setColor(1f, 0.78f, 0.25f, 1f); pm.fillCircle(38, (cy + s * 4f).toInt(), 2)
        }
        return pm
    }

    /** A top-down survivor facing +x: shoulders, helmet, both hands on a rifle. Tinted per player by the caller. */
    private fun soldier(size: Int): Pixmap {
        val pm = Pixmap(size, size, Pixmap.Format.RGBA8888)
        val cy = size / 2f
        val olive = Color(0.30f, 0.34f, 0.24f, 1f)
        pm.ellipse(24f, cy, 11.5f, 19.5f, shade(olive, 0.45f))
        pm.ellipse(24f, cy, 10f, 18f, olive)
        pm.setColor(0.17f, 0.18f, 0.14f, 1f); pm.fillRectangle(10, (cy - 8).toInt(), 6, 16) // pack
        pm.thick(27f, cy - 15f, 46f, cy - 3f, 6f, shade(olive, 0.8f)); pm.thick(27f, cy + 15f, 46f, cy + 3f, 6f, shade(olive, 0.8f))
        pm.setColor(0.2f, 0.21f, 0.23f, 1f); pm.fillRectangle(30, (cy - 3).toInt(), 28, 6) // rifle
        pm.setColor(0.32f, 0.33f, 0.36f, 1f); pm.fillRectangle(56, (cy - 2).toInt(), 6, 4)
        pm.setColor(0.12f, 0.12f, 0.13f, 1f); pm.fillRectangle(40, (cy + 3).toInt(), 5, 6) // magazine
        pm.setColor(shade(olive, 0.45f)); pm.fillCircle(30, cy.toInt(), 11) // helmet rim
        pm.setColor(0.27f, 0.30f, 0.21f, 1f); pm.fillCircle(30, cy.toInt(), 9.coerceAtLeast(1))
        pm.setColor(0.36f, 0.4f, 0.29f, 1f); pm.fillCircle(28, (cy - 2).toInt(), 4) // highlight
        pm.setColor(0.76f, 0.62f, 0.5f, 1f); pm.fillCircle(36, cy.toInt(), 2) // a hint of face under the brim
        return pm
    }

    // ---- effects ----------------------------------------------------------------------------------------------------
    private class Decal(val x: Float, val y: Float, val rot: Float, val scale: Float, val idx: Int) { var age = 0f }
    private class Flash(val x: Float, val y: Float, var life: Float)
    private val decals = ArrayList<Decal>()
    private val flashes = ArrayList<Flash>()

    /** A blood splat on the floor. The oldest are dropped past a fixed cap so the cost stays bounded. */
    fun addBlood(x: Float, y: Float, scale: Float = 1f) {
        decals += Decal(x + (rnd.nextFloat() - 0.5f) * 10f, y + (rnd.nextFloat() - 0.5f) * 10f, rnd.nextFloat() * 360f, (0.7f + rnd.nextFloat() * 0.7f) * scale, rnd.nextInt(splats.size))
        if (decals.size > MAX_DECALS) decals.removeAt(0)
    }

    fun muzzle(x: Float, y: Float) { flashes += Flash(x, y, 0.07f); if (flashes.size > 24) flashes.removeAt(0) }

    fun update(dt: Float) {
        for (d in decals) d.age += dt
        val it = flashes.iterator(); while (it.hasNext()) { val f = it.next(); f.life -= dt; if (f.life <= 0f) it.remove() }
    }

    fun clearDecals() { decals.clear(); flashes.clear() }

    // ---- drawing (all take an active SpriteBatch) -------------------------------------------------------------------
    fun drawFloor(batch: SpriteBatch, x: Float, y: Float, w: Float, h: Float, tile: Float = 128f) {
        batch.setColor(1f, 1f, 1f, 1f)
        batch.draw(floor, x, y, w, h, 0f, h / tile, w / tile, 0f)
    }

    private class Grime(val x: Float, val y: Float, val r: Float, val a: Float)
    private var grime: List<Grime>? = null

    /** Large soft dark blotches over the floor so the repeating concrete tile does not show. Deterministic. */
    fun drawGrime(batch: SpriteBatch, x: Float, y: Float, w: Float, h: Float) {
        val g = grime ?: List(38) { Grime(x + rnd.nextFloat() * w, y + rnd.nextFloat() * h, 50f + rnd.nextFloat() * 110f, 0.10f + rnd.nextFloat() * 0.16f) }.also { grime = it }
        for (b in g) { batch.setColor(0f, 0f, 0f, b.a); batch.draw(glow, b.x - b.r, b.y - b.r * 0.8f, b.r * 2, b.r * 1.6f) }
        batch.setColor(1f, 1f, 1f, 1f)
    }

    fun drawDecals(batch: SpriteBatch) {
        for (d in decals) {
            val fade = if (d.age < 50f) 1f else (1f - (d.age - 50f) / 60f).coerceAtLeast(0.25f)
            batch.setColor(1f, 1f, 1f, 0.8f * fade)
            val s = 80f * d.scale
            batch.draw(splats[d.idx], d.x - s / 2, d.y - s / 2, s / 2, s / 2, s, s, 1f, 1f, d.rot)
        }
        batch.setColor(1f, 1f, 1f, 1f)
    }

    inline fun additive(batch: SpriteBatch, block: () -> Unit) {
        batch.setBlendFunction(GL20.GL_SRC_ALPHA, GL20.GL_ONE); block(); batch.setBlendFunction(GL20.GL_SRC_ALPHA, GL20.GL_ONE_MINUS_SRC_ALPHA)
    }

    /** A soft light of radius [r] (additive, so call inside [additive]). */
    fun light(batch: SpriteBatch, x: Float, y: Float, r: Float, red: Float, green: Float, blue: Float, a: Float) {
        batch.setColor(red, green, blue, a); batch.draw(glow, x - r, y - r, r * 2, r * 2); batch.setColor(1f, 1f, 1f, 1f)
    }

    fun drawFlashes(batch: SpriteBatch) { for (f in flashes) light(batch, f.x, f.y, 90f * (0.5f + f.life / 0.07f * 0.5f), 1f, 0.8f, 0.4f, 0.9f * f.life / 0.07f) }

    fun shadow(batch: SpriteBatch, x: Float, y: Float, r: Float) { batch.setColor(0f, 0f, 0f, 0.45f); batch.draw(glow, x - r * 1.2f, y - r * 1.0f - 3f, r * 2.4f, r * 2f); batch.setColor(1f, 1f, 1f, 1f) }

    /** Draws a sprite of [size] world units centred on (x, y) facing [angleDeg] (the art faces +x). */
    fun sprite(batch: SpriteBatch, region: TextureRegion, x: Float, y: Float, size: Float, angleDeg: Float, tint: Color = Color.WHITE) {
        batch.setColor(tint); batch.draw(region, x - size / 2, y - size / 2, size / 2, size / 2, size, size, 1f, 1f, angleDeg); batch.setColor(1f, 1f, 1f, 1f)
    }

    /** Full-screen edge darkening, tinted (for example black, or red when hurt). */
    fun drawVignette(batch: SpriteBatch, w: Float, h: Float, r: Float, g: Float, b: Float, a: Float) {
        if (a <= 0.005f) return
        batch.setColor(r, g, b, a.coerceAtMost(1f)); batch.draw(vignette, 0f, 0f, w, h); batch.setColor(1f, 1f, 1f, 1f)
    }

    /** Text with a dark outline so it stays readable on any background. Caller sets the font scale. */
    fun outlined(batch: SpriteBatch, font: BitmapFont, text: String, x: Float, y: Float, color: Color, o: Float = 2f) {
        val old = font.color.cpy()
        font.setColor(0f, 0f, 0f, 0.85f * color.a)
        font.draw(batch, text, x - o, y); font.draw(batch, text, x + o, y); font.draw(batch, text, x, y - o); font.draw(batch, text, x, y + o)
        font.draw(batch, text, x + o, y - o)
        font.color = color; font.draw(batch, text, x, y); font.color = old
    }

    override fun dispose() { textures.forEach { it.dispose() }; textures.clear() }

    private companion object { const val MAX_DECALS = 140 }
}
