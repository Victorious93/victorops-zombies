package com.victorious.zombie

import com.badlogic.gdx.Application
import com.badlogic.gdx.Gdx
import com.badlogic.gdx.Input
import com.badlogic.gdx.ScreenAdapter
import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.GL20
import com.badlogic.gdx.graphics.OrthographicCamera
import com.badlogic.gdx.graphics.g2d.BitmapFont
import com.badlogic.gdx.graphics.g2d.GlyphLayout
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.badlogic.gdx.graphics.glutils.ShapeRenderer
import com.badlogic.gdx.math.MathUtils
import com.badlogic.gdx.math.Vector2
import com.badlogic.gdx.math.Vector3
import com.badlogic.gdx.utils.viewport.FitViewport
import com.victorious.zombie.logic.*
import com.victorious.zombie.net.ClientSession
import com.victorious.zombie.net.HostSession
import com.victorious.zombie.sim.Layout
import com.victorious.zombie.sim.PlayerInput
import com.victorious.zombie.sim.PlayerSnap
import com.victorious.zombie.sim.Snapshot
import com.victorious.zombie.sim.World
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** How this screen gets its game state. Solo and Host run the [World] locally; Client renders what the host sends. */
sealed class Mode {
    /** Offline single player. Never touches the network. */
    object Solo : Mode()
    /** Runs the world and serves peers attached to [session] (Wi-Fi, Bluetooth, ...). */
    class Host(val session: HostSession, val onClose: () -> Unit = {}) : Mode()
    class Client(val session: ClientSession) : Mode()
}

/** Playable game. All visuals are procedural placeholder shapes. */
class GameScreen(private val character: Character = Characters.DEFAULT, private val mode: Mode = Mode.Solo) : ScreenAdapter() {
    private val W = Layout.W; private val H = Layout.H
    private val cam = OrthographicCamera(); private val view = FitViewport(W, H, cam)
    private val shapes = ShapeRenderer(); private val batch = SpriteBatch(); private val font = BitmapFont()
    private val tmp = Vector3()
    private val playerColors = listOf(Color(0.1f, 0.95f, 1f, 1f), Color(1f, 0.6f, 0.2f, 1f), Color(0.5f, 1f, 0.4f, 1f), Color(1f, 0.4f, 0.9f, 1f))
    private val magenta = Color(1f, 0.15f, 0.85f, 1f)

    // Local simulation (Solo/Host only)
    private val host: HostSession? = when (mode) {
        is Mode.Solo -> HostSession.create(character)
        is Mode.Host -> mode.session
        is Mode.Client -> null
    }
    private val client: ClientSession? = (mode as? Mode.Client)?.session
    private val localId: Int get() = client?.playerId ?: HostSession.HOST_ID

    // Touch controls
    private val isTouch = Gdx.app.type == Application.ApplicationType.Android || System.getProperty("zombie.touch") == "1" // the property lets the desktop harness draw the phone HUD
    /** Text scale: the default font is about 1 mm tall on a 6-inch phone at this virtual size, so touch devices get bigger type. */
    private val ui = if (isTouch) 1.6f else 1f
    init { font.data.setScale(ui) }
    private val look = Look()
    private val stickCenter = Vector2(150f, 150f); private val stick = Vector2()
    private val useBtn = Vector2(W - 130f, 130f); private val abilityBtn = Vector2(W - 280f, 110f)
    private var useTouched = false; private var abilityTouched = false

    private var snap: Snapshot? = null
    private var disposed = false
    private var done = false // GL resources are disposed after leaving; never draw after that
    private val shown = HashMap<Int, Vector2>() // smoothed positions for network clients

    // visual effect state
    private val prevPos = HashMap<Int, Vector2>(); private val heading = HashMap<Int, Float>()
    private val seenZombies = HashMap<Int, Vector2>() // id -> last position, to put blood where a zombie died
    private val lastFlash = HashMap<Int, Float>()
    private class Pop(var value: Int, var age: Float = 0f)
    private val pops = ArrayList<Pop>()
    private var lastPoints = -1; private var lastRound = -1; private var lastHealth = -1f
    private var hurtT = 0f; private var roundFlashT = 0f; private var time = 0f

    override fun resize(width: Int, height: Int) { view.update(width, height, true) }

    override fun render(delta: Float) {
        if (done) return
        val dt = minOf(delta, 1 / 30f)
        val input = readInput()
        host?.world?.setInput(HostSession.HOST_ID, input)
        host?.tick(dt)
        client?.tick(dt, input)
        snap = host?.world?.snapshot(HostSession.HOST_ID) ?: client?.latest

        val s = snap
        val restartPressed = Gdx.input.justTouched() || Gdx.input.isKeyJustPressed(Input.Keys.ENTER)
        if (restartPressed) when {
            client != null && (!client.connected || client.rejected) -> backToMenu()
            s != null && s.gameOver && host != null -> host.world.reset()
        }
        if (!done) draw(s, dt)
    }

    private fun backToMenu() {
        if (done) return
        done = true
        (Gdx.app.applicationListener as? VictorOpsGame)?.setScreen(CharacterSelectScreen()); dispose()
    }

    private fun readInput(): PlayerInput {
        var dx = 0f; var dy = 0f
        if (Gdx.input.isKeyPressed(Input.Keys.W)) dy += 1
        if (Gdx.input.isKeyPressed(Input.Keys.S)) dy -= 1
        if (Gdx.input.isKeyPressed(Input.Keys.A)) dx -= 1
        if (Gdx.input.isKeyPressed(Input.Keys.D)) dx += 1
        useTouched = false; abilityTouched = false; stick.setZero()
        var stickActive = false
        for (p in 0 until 5) {
            if (!Gdx.input.isTouched(p)) continue
            view.unproject(tmp.set(Gdx.input.getX(p).toFloat(), Gdx.input.getY(p).toFloat(), 0f))
            if (tmp.x < W / 2) { stick.set(tmp.x - stickCenter.x, tmp.y - stickCenter.y).limit(90f); stickActive = true }
            else if (Vector2.dst(tmp.x, tmp.y, useBtn.x, useBtn.y) < 90f) useTouched = true
            else if (Vector2.dst(tmp.x, tmp.y, abilityBtn.x, abilityBtn.y) < 70f) abilityTouched = true
        }
        if (stickActive) { dx = stick.x / 90f; dy = stick.y / 90f }
        return PlayerInput(dx, dy, Gdx.input.isKeyPressed(Input.Keys.E) || useTouched, Gdx.input.isKeyPressed(Input.Keys.Q) || abilityTouched)
    }

    /** Clients ease toward the last known position so 15 Hz updates look smooth; the host draws exact positions. */
    private fun pos(key: Int, x: Float, y: Float, dt: Float): Vector2 {
        if (client == null) return tmp2.set(x, y)
        if (shown.size > 600) shown.clear()
        val v = shown.getOrPut(key) { Vector2(x, y) }
        val k = 1f - Math.exp((-18f * dt).toDouble()).toFloat()
        v.x += (x - v.x) * k; v.y += (y - v.y) * k
        return v
    }
    private val tmp2 = Vector2()

    /** Direction an entity is moving (radians), remembered while it stands still. */
    private fun headingOf(key: Int, p: Vector2, fallback: Float): Float {
        val prev = prevPos.getOrPut(key) { Vector2(p) }
        val dx = p.x - prev.x; val dy = p.y - prev.y
        if (dx * dx + dy * dy > 0.04f) heading[key] = atan2(dy, dx)
        prev.set(p)
        return heading[key] ?: fallback
    }

    /** Starts a shape pass with alpha blending on: SpriteBatch.end() switches blending off, which makes translucent shapes opaque. */
    private fun beginShapes(type: ShapeRenderer.ShapeType = ShapeRenderer.ShapeType.Filled) {
        Gdx.gl.glEnable(GL20.GL_BLEND); Gdx.gl.glBlendFunc(GL20.GL_SRC_ALPHA, GL20.GL_ONE_MINUS_SRC_ALPHA)
        shapes.begin(type)
    }

    /** Turns snapshot changes into effects: blood where zombies die, point popups, hurt flashes, round banners, muzzle flashes. */
    private fun track(s: Snapshot, me: PlayerSnap?, dt: Float) {
        if (lastRound >= 0 && s.round < lastRound) { look.clearDecals(); seenZombies.clear(); pops.clear() } // a fresh game
        if (s.round != lastRound) { roundFlashT = 3.2f; lastRound = s.round }
        val ids = HashSet<Int>(s.zombies.size * 2)
        for (z in s.zombies) { ids += z.id; seenZombies.getOrPut(z.id) { Vector2() }.set(z.x, z.y) }
        val it = seenZombies.entries.iterator()
        while (it.hasNext()) { val e = it.next(); if (e.key !in ids) { look.addBlood(e.value.x, e.value.y); it.remove() } }
        if (me != null) {
            if (lastPoints >= 0 && me.points != lastPoints) {
                val d = me.points - lastPoints; val last = pops.lastOrNull()
                if (last != null && last.age < 0.4f && (last.value > 0) == (d > 0)) { last.value += d; last.age = 0f } else pops += Pop(d)
            }
            lastPoints = me.points
            if (lastHealth >= 0f && me.health < lastHealth - 0.5f) hurtT = min(1f, hurtT + 0.55f)
            lastHealth = me.health
        }
        for (p in s.players) if (!p.downed) for (b in s.bullets) {
            if (hypot(b.x - p.x, b.y - p.y) < 48f && time - (lastFlash[p.id] ?: -1f) > 0.06f) { lastFlash[p.id] = time; look.muzzle(p.x, p.y); break }
        }
        hurtT = max(0f, hurtT - dt * 1.7f); roundFlashT = max(0f, roundFlashT - dt)
        for (p in pops) p.age += dt
        pops.removeAll { it.age > 1.1f }
        if (pops.size > 8) pops.removeAt(0)
    }

    private fun draw(s: Snapshot?, dt: Float) {
        time += dt; look.update(dt)
        Gdx.gl.glClearColor(0.012f, 0.011f, 0.016f, 1f); Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT)
        view.apply(); shapes.projectionMatrix = cam.combined; batch.projectionMatrix = cam.combined
        if (s == null) {
            batch.begin(); font.color = Color.WHITE
            val msg = if (client != null && (!client.connected || client.rejected)) "Could not join (host full or gone). Tap to go back." else "Connecting..."
            font.data.setScale(1.2f * ui); layout.setText(font, msg); look.outlined(batch, font, msg, W / 2 - layout.width / 2, H / 2, Color.WHITE); font.data.setScale(ui)
            batch.end(); return
        }
        val me = s.players.firstOrNull { it.id == localId }
        track(s, me, dt)

        // 1. floor and blood
        batch.begin()
        look.drawFloor(batch, Layout.MIN_X, Layout.MIN_Y, Layout.MAX_X - Layout.MIN_X, Layout.MAX_Y - Layout.MIN_Y)
        look.drawGrime(batch, Layout.MIN_X, Layout.MIN_Y, Layout.MAX_X - Layout.MIN_X, Layout.MAX_Y - Layout.MIN_Y)
        look.drawDecals(batch)
        batch.end()
        // 2. walls, windows, boards, machines
        beginShapes(); drawStructures(s); shapes.end()
        // 3. actors
        batch.begin(); drawActors(s, dt); batch.end()
        // 4. darkness, then lights that cut through it
        beginShapes(); shapes.setColor(0.0f, 0.0f, 0.03f, 0.42f); shapes.rect(0f, 0f, W, H); shapes.end()
        batch.begin(); drawLights(s); drawSurvivors(s, dt); batch.end()
        // 5. world-space text, vignette and the HUD
        batch.begin()
        drawWorldText(s, dt)
        look.drawVignette(batch, W, H, 0f, 0f, 0f, 0.8f)
        val low = if (me != null && !me.downed) (1f - (me.health / me.maxHealth) * 2.2f).coerceIn(0f, 1f) else 0f
        val pulse = if (low > 0f) 0.5f + 0.5f * sin(time * 6f) else 0f
        look.drawVignette(batch, W, H, 0.55f, 0f, 0f, max(hurtT * 0.9f, low * (0.35f + 0.25f * pulse)))
        batch.end()
        drawHud(s, me, dt)
    }

    // ---- world structures ------------------------------------------------------------------------------------------
    private fun drawStructures(s: Snapshot) {
        val t = 30f; val x0 = Layout.MIN_X; val x1 = Layout.MAX_X; val y0 = Layout.MIN_Y; val y1 = Layout.MAX_Y
        // brick walls: four bands centred on the arena edge
        fun band(x: Float, y: Float, w: Float, h: Float) {
            shapes.setColor(0.17f, 0.15f, 0.15f, 1f); shapes.rect(x, y, w, h)
            shapes.setColor(0.11f, 0.095f, 0.10f, 1f)
            if (w > h) { var bx = x + 6f; var row = 0; while (bx < x + w) { shapes.rect(bx, y + (if (row % 2 == 0) 0f else h / 2), 1.5f, h / 2); bx += 26f; row++ }; shapes.rect(x, y + h / 2 - 0.75f, w, 1.5f) }
            else { var by = y + 6f; var row = 0; while (by < y + h) { shapes.rect(x + (if (row % 2 == 0) 0f else w / 2), by, w / 2, 1.5f); by += 26f; row++ }; shapes.rect(x + w / 2 - 0.75f, y, 1.5f, h) }
            shapes.setColor(0.30f, 0.27f, 0.26f, 1f); if (w > h) shapes.rect(x, y + h - 3f, w, 3f) else shapes.rect(x + w - 3f, y, 3f, h)
        }
        band(x0 - t / 2, y1 - t / 2, x1 - x0 + t, t); band(x0 - t / 2, y0 - t / 2, x1 - x0 + t, t)
        band(x0 - t / 2, y0 - t / 2, t, y1 - y0 + t); band(x1 - t / 2, y0 - t / 2, t, y1 - y0 + t)
        // windows with nailed boards
        Layout.windows.forEachIndexed { i, w ->
            val horizontal = i < 2; val planks = ((s.barricadeHp.getOrElse(i) { 0 }) + 49) / 50
            val cx = w.inside.x; val cy = w.inside.y; val len = 130f
            // opening and frame
            shapes.setColor(0.30f, 0.20f, 0.11f, 1f)
            if (horizontal) shapes.rect(cx - len / 2 - 5, cy - t / 2 - 2, len + 10, t + 4) else shapes.rect(cx - t / 2 - 2, cy - len / 2 - 5, t + 4, len + 10)
            shapes.setColor(0.02f, 0.02f, 0.035f, 1f)
            if (horizontal) shapes.rect(cx - len / 2, cy - t / 2, len, t) else shapes.rect(cx - t / 2, cy - len / 2, t, len)
            for (k in 0 until planks) {
                val j = ((k * 37 + i * 11) % 7 - 3) * 0.9f
                val tone = 0.40f + ((k * 13) % 5) * 0.025f
                shapes.setColor(tone, tone * 0.64f, tone * 0.36f, 1f)
                val off = -t / 2 + 3f + k * (t - 6f) / 6f
                if (horizontal) { shapes.rectLine(cx - len / 2 - 2, cy + off + j * 0.4f, cx + len / 2 + 2, cy + off - j * 0.4f, 4.2f); shapes.setColor(0.1f, 0.1f, 0.1f, 1f); shapes.circle(cx - len / 2 + 4, cy + off, 1.4f); shapes.circle(cx + len / 2 - 4, cy + off, 1.4f) }
                else { shapes.rectLine(cx + off + j * 0.4f, cy - len / 2 - 2, cx + off - j * 0.4f, cy + len / 2 + 2, 4.2f); shapes.setColor(0.1f, 0.1f, 0.1f, 1f); shapes.circle(cx + off, cy - len / 2 + 4, 1.4f); shapes.circle(cx + off, cy + len / 2 - 4, 1.4f) }
            }
            // torn boards lying on the floor inside
            for (k in 0 until min(6 - planks, 3)) {
                shapes.setColor(0.30f, 0.19f, 0.10f, 1f)
                val ox = (if (horizontal) (k - 1) * 34f else if (i == 2) 26f + k * 6f else -26f - k * 6f); val oy = (if (horizontal) (if (i == 0) -22f - k * 5f else 22f + k * 5f) else (k - 1) * 30f)
                shapes.rectLine(cx + ox - 12, cy + oy - 3 * (k - 1), cx + ox + 12, cy + oy + 3 * (k - 1), 4f)
            }
        }
        // mystery crate
        val b = Layout.box
        shapes.setColor(0.05f, 0.04f, 0.03f, 0.6f); shapes.rect(b.x - 33, b.y - 22, 66f, 40f)
        shapes.setColor(0.36f, 0.22f, 0.10f, 1f); shapes.rect(b.x - 31, b.y - 19, 62f, 38f)
        shapes.setColor(0.22f, 0.13f, 0.06f, 1f); shapes.rect(b.x - 31, b.y - 19, 62f, 4f); shapes.rect(b.x - 31, b.y + 15, 62f, 4f)
        shapes.setColor(0.85f, 0.66f, 0.18f, 1f); shapes.rect(b.x - 31, b.y - 3, 62f, 6f); shapes.rect(b.x - 31, b.y - 19, 6f, 38f); shapes.rect(b.x + 25, b.y - 19, 6f, 38f)
        // perk machine
        val pk = Layout.perk
        shapes.setColor(0.04f, 0.05f, 0.04f, 0.6f); shapes.rect(pk.x - 21, pk.y - 33, 42f, 66f)
        shapes.setColor(0.10f, 0.13f, 0.10f, 1f); shapes.rect(pk.x - 19, pk.y - 31, 38f, 62f)
        val perkPulse = 0.75f + 0.25f * sin(time * 3f)
        shapes.setColor(0.3f * perkPulse, 0.95f * perkPulse, 0.25f * perkPulse, 1f); shapes.rect(pk.x - 12, pk.y - 22, 24f, 30f)
        shapes.setColor(0.06f, 0.07f, 0.06f, 1f); shapes.rect(pk.x - 12, pk.y - 22, 24f, 3f); shapes.rect(pk.x - 12, pk.y - 2, 24f, 3f); shapes.rect(pk.x - 8, pk.y + 14, 16f, 10f)
        // upgrade forge
        val f = Layout.forge
        shapes.setColor(0.06f, 0.04f, 0.07f, 0.6f); shapes.rect(f.x - 33, f.y - 33, 66f, 66f)
        shapes.setColor(0.16f, 0.12f, 0.18f, 1f); shapes.rect(f.x - 31, f.y - 31, 62f, 62f)
        shapes.setColor(0.1f, 0.07f, 0.12f, 1f); shapes.rect(f.x - 24, f.y - 24, 48f, 48f)
        val core = 0.7f + 0.3f * sin(time * 4.2f)
        shapes.setColor(1f * core, 0.15f * core, 0.8f * core, 1f); shapes.circle(f.x, f.y, 13f, 24)
        shapes.setColor(1f, 0.7f, 0.95f, 1f); shapes.circle(f.x, f.y, 5f, 12)
        // armor lockers
        val stripes = listOf(Color(0.4f, 0.65f, 0.95f, 1f), Color(0.35f, 0.85f, 0.55f, 1f), Color(0.95f, 0.72f, 0.28f, 1f))
        Layout.armorStations.forEachIndexed { i, (p, _) ->
            shapes.setColor(0.03f, 0.03f, 0.04f, 0.6f); shapes.rect(p.x - 26, p.y - 30, 52f, 60f)
            shapes.setColor(0.20f, 0.23f, 0.29f, 1f); shapes.rect(p.x - 24, p.y - 28, 48f, 56f)
            shapes.setColor(0.13f, 0.15f, 0.19f, 1f); shapes.rect(p.x - 2, p.y - 28, 4f, 56f); shapes.rect(p.x - 24, p.y + 12, 48f, 3f)
            shapes.color = stripes[i % 3]; shapes.rect(p.x - 24, p.y + 17, 48f, 6f)
        }
        // armor pickups
        for (pk2 in s.pickups) { shapes.setColor(0.1f, 0.2f, 0.35f, 1f); shapes.rect(pk2.x - 9, pk2.y - 9, 18f, 18f); shapes.setColor(0.45f, 0.75f, 1f, 1f); shapes.rect(pk2.x - 6, pk2.y - 6, 12f, 12f) }
    }

    // ---- zombies, survivors, bullets ------------------------------------------------------------------------------
    private fun drawActors(s: Snapshot, dt: Float) {
        // soft ground shadows
        for (z in s.zombies) { val p = pos(z.id + 10_000, z.x, z.y, dt); look.shadow(batch, p.x, p.y, 17f) }
        for (pl in s.players) { val p = pos(pl.id, pl.x, pl.y, dt); look.shadow(batch, p.x, p.y, 16f) }
        // zombies face where they are heading
        for (z in s.zombies) {
            val p = pos(z.id + 10_000, z.x, z.y, dt)
            val ang = headingOf(z.id + 10_000, p, -1.57f)
            look.sprite(batch, look.zombieSprites[z.id % look.zombieSprites.size], p.x, p.y, 62f, Math.toDegrees(ang.toDouble()).toFloat())
        }
    }

    /** Drawn after the lighting pass: survivors are lit, never blown out by their own torch. */
    private fun drawSurvivors(s: Snapshot, dt: Float) {
        // survivors face the nearest zombie (the auto-aim target) or the way they walk
        for (pl in s.players) {
            val p = pos(pl.id, pl.x, pl.y, dt)
            var ang = headingOf(pl.id, p, 0f)
            var best = 520f * 520f; var tx = 0f; var ty = 0f; var found = false
            for (z in s.zombies) { val d = (z.x - p.x) * (z.x - p.x) + (z.y - p.y) * (z.y - p.y); if (d < best) { best = d; tx = z.x; ty = z.y; found = true } }
            if (found && !pl.downed) ang = atan2(ty - p.y, tx - p.x)
            val col = playerColors[pl.id % playerColors.size]
            look.additive(batch) { look.light(batch, p.x, p.y, 26f, col.r, col.g, col.b, if (pl.id == localId) 0.30f else 0.2f) }
            val tint = if (pl.downed) Color(0.5f, 0.5f, 0.55f, 0.8f) else Color.WHITE
            look.sprite(batch, look.soldier, p.x, p.y, 60f, Math.toDegrees(ang.toDouble()).toFloat(), tint)
        }
    }

    // ---- lighting (additive, over the darkness) --------------------------------------------------------------------
    private fun drawLights(s: Snapshot) {
        look.additive(batch) {
            for (pl in s.players) if (!pl.downed) { val p = pos(pl.id, pl.x, pl.y, 0f); look.light(batch, p.x, p.y, if (pl.id == localId) 360f else 260f, 1f, 0.86f, 0.62f, if (pl.id == localId) 0.36f else 0.24f) }
            for (b in s.bullets) look.light(batch, b.x, b.y, 14f, 1f, 0.9f, 0.5f, 0.9f)
            look.drawFlashes(batch)
            val b = Layout.box; val beam = 0.2f + 0.08f * sin(time * 2.4f)
            look.light(batch, b.x, b.y, 120f, 1f, 0.78f, 0.25f, 0.32f)
            batch.setColor(1f, 0.82f, 0.3f, beam); batch.draw(look.glow, b.x - 26f, b.y, 52f, 360f); batch.setColor(1f, 1f, 1f, 1f)
            look.light(batch, Layout.perk.x, Layout.perk.y, 120f, 0.35f, 1f, 0.3f, 0.3f)
            look.light(batch, Layout.forge.x, Layout.forge.y, 140f, 1f, 0.2f, 0.85f, 0.26f + 0.1f * sin(time * 4.2f))
            Layout.armorStations.forEach { (p, _) -> look.light(batch, p.x, p.y, 62f, 0.4f, 0.6f, 1f, 0.16f) }
            Layout.windows.forEach { w -> look.light(batch, w.inside.x, w.inside.y, 110f, 0.35f, 0.5f, 0.85f, 0.10f) }
            for (pk in s.pickups) look.light(batch, pk.x, pk.y, 36f, 0.4f, 0.7f, 1f, 0.5f)
        }
    }

    private fun drawWorldText(s: Snapshot, dt: Float) {
        val b = Layout.box
        font.data.setScale(1.6f * ui); layout.setText(font, "?"); look.outlined(batch, font, "?", b.x - layout.width / 2, b.y + 14f * ui, Color(1f, 0.85f, 0.3f, 1f)); font.data.setScale(ui)
        for (pl in s.players) {
            val p = pos(pl.id, pl.x, pl.y, dt)
            if (pl.bark.isNotEmpty()) { font.data.setScale(0.9f * ui); layout.setText(font, pl.bark); look.outlined(batch, font, pl.bark, p.x - layout.width / 2, p.y + 56f, Color(1f, 0.9f, 0.4f, 1f), 1.5f); font.data.setScale(ui) }
            if (s.players.size > 1) { val nm = Characters.byId(pl.characterId).name.substringBefore(' '); font.data.setScale(0.8f * ui); layout.setText(font, nm); look.outlined(batch, font, nm, p.x - layout.width / 2, p.y - 24f, playerColors[pl.id % playerColors.size], 1.5f); font.data.setScale(ui) }
        }
    }

    // ---- HUD -------------------------------------------------------------------------------------------------------
    private fun drawHud(s: Snapshot, me: PlayerSnap?, dt: Float) {
        val u = ui
        val rows = if (s.round <= 25) (s.round + 24) / 25 else 0
        // tally marks (groups of five with a strike) in the top-left, blood red for a moment when the round changes
        beginShapes()
        val x0 = 26f; val top = H - 24f; val markH = 30f * u; val gap = 8f * u; val groupW = 4 * gap + 14f * u
        if (s.round in 1..25) {
            val flash = (roundFlashT / 3.2f).coerceIn(0f, 1f)
            for (r in 1..s.round) {
                val idx = r - 1; val g = idx / 5; val k = idx % 5; val gx = x0 + (g % 5) * (groupW + 10f * u); val gy = top - (g / 5) * (markH + 12f * u)
                val newest = r == s.round
                shapes.color = if (newest && flash > 0f) Color(0.85f, 0.1f, 0.08f, 1f).lerp(Color(0.93f, 0.9f, 0.84f, 1f), 1f - flash) else Color(0.93f, 0.9f, 0.84f, 0.92f)
                if (k < 4) shapes.rectLine(gx + k * gap + ((idx * 7) % 3 - 1) * 0.6f, gy, gx + k * gap - ((idx * 5) % 3 - 1) * 0.6f, gy - markH, 3.2f * u)
                else shapes.rectLine(gx - 5f * u, gy - markH * 0.15f, gx + 3 * gap + 6f * u, gy - markH * 0.85f, 3.2f * u)
            }
        }
        val tallyBottom = top - max(0, rows - 1) * (markH + 12f * u) - markH
        // health and armor: thin bars under the points (the screen edge also reddens when hurt)
        val barY = tallyBottom - 62f * u
        if (me != null) {
            shapes.setColor(0f, 0f, 0f, 0.55f); shapes.rect(x0 - 3, barY - 3, 150f * u + 6, 12f * u + 6)
            shapes.setColor(0.75f, 0.08f, 0.08f, 1f); shapes.rect(x0, barY + 5f * u, 150f * u * (me.health / me.maxHealth).coerceAtLeast(0f), 7f * u)
            shapes.setColor(0.35f, 0.65f, 0.95f, 1f); shapes.rect(x0, barY, 150f * u * (me.armor / 200f).coerceIn(0f, 1f), 3.5f * u)
            if (me.downed) { shapes.setColor(0.3f, 1f, 0.4f, 1f); shapes.rect(W / 2 - 60, 170f, 120f * me.reviveProgress, 6f) }
        }
        if (isTouch) {
            shapes.setColor(1f, 1f, 1f, 0.10f); shapes.circle(stickCenter.x, stickCenter.y, 90f, 36)
            shapes.setColor(0.7f, 0.95f, 1f, 0.40f); shapes.circle(stickCenter.x + stick.x, stickCenter.y + stick.y, 35f, 24)
            shapes.setColor(0.8f, 0.1f, 0.1f, 0.35f); shapes.circle(useBtn.x, useBtn.y, 60f, 32)
            shapes.setColor(1f, 0.8f, 0.1f, if (me != null && me.abilityCd <= 0f) 0.5f else 0.15f); shapes.circle(abilityBtn.x, abilityBtn.y, 50f, 28)
        }
        shapes.end()

        batch.begin(); font.color = Color.WHITE
        // round: big numeral when the tally would be too long, and a red banner at the start of each round
        if (s.round > 25) { font.data.setScale(2.2f * u); look.outlined(batch, font, "${s.round}", x0, top, Color(0.75f, 0.06f, 0.06f, 1f)); font.data.setScale(u) }
        // points with popups
        if (me != null) {
            val py = tallyBottom - 14f * u
            font.data.setScale(1.7f * u); look.outlined(batch, font, "${me.points}", x0, py, Color(0.98f, 0.93f, 0.8f, 1f)); font.data.setScale(u)
            for (p in pops) {
                val k = p.age / 1.1f; val gain = p.value > 0
                font.data.setScale(1.1f * u)
                look.outlined(batch, font, if (gain) "+${p.value}" else "${p.value}", x0 + 110f * u, py - 4f - 46f * k * u, if (gain) Color(1f, 0.85f, 0.25f, 1f - k * k) else Color(0.9f, 0.3f, 0.3f, 1f - k * k), 1.5f)
                font.data.setScale(u)
            }
        }
        // weapon and ammo, top-right
        if (me != null) {
            val ammo = if (me.reloading) "RELOAD" else "${me.rounds}"
            font.data.setScale(2.4f * u); layout.setText(font, ammo)
            look.outlined(batch, font, ammo, W - 26f - layout.width, H - 22f, if (me.reloading) Color(1f, 0.7f, 0.2f, 1f) else if (me.rounds <= me.weapon.magSize / 4) Color(1f, 0.45f, 0.35f, 1f) else Color.WHITE)
            val ay = H - 22f - layout.height - 10f * u
            font.data.setScale(0.95f * u); val gun = me.weapon.displayName + "  /  " + me.weapon.magSize; layout.setText(font, gun)
            look.outlined(batch, font, gun, W - 26f - layout.width, ay, Color(0.85f, 0.85f, 0.8f, 1f), 1.5f)
            val ch = Characters.byId(me.characterId); val ab = ch.abilityName.uppercase() + if (me.abilityCd <= 0f) "  READY" else "  ${me.abilityCd.toInt()}s"; layout.setText(font, ab)
            look.outlined(batch, font, ab, W - 26f - layout.width, ay - 22f * u, if (me.abilityCd <= 0f) Color(1f, 0.82f, 0.25f, 1f) else Color(0.6f, 0.6f, 0.6f, 1f), 1.5f)
            if (me.perkOwned) { val pt = "IRON HIDE"; layout.setText(font, pt); look.outlined(batch, font, pt, W - 26f - layout.width, ay - 44f * u, Color(0.4f, 1f, 0.35f, 1f), 1.5f) }
            font.data.setScale(u)
        }
        if (s.players.size > 1) {
            var y = H - 150f * u - 20f; font.data.setScale(0.8f * u)
            for (p in s.players) { val line = "${Characters.byId(p.characterId).name.substringBefore(' ')}  ${if (p.downed) "DOWN" else "HP ${p.health.toInt()}"}  ${p.points}"; layout.setText(font, line); look.outlined(batch, font, line, W - 26f - layout.width, y, if (p.downed) Color(1f, 0.4f, 0.4f, 1f) else Color(0.85f, 0.85f, 0.8f, 1f), 1.5f); y -= 18f * u }
            font.data.setScale(u)
        }
        // buy / use prompt
        if (s.prompt.isNotEmpty()) { val t = s.prompt + if (isTouch) "   (tap USE)" else "   (press E)"; font.data.setScale(1.1f * u); layout.setText(font, t); look.outlined(batch, font, t, W / 2 - layout.width / 2, 120f, Color.WHITE); font.data.setScale(u) }
        if (s.message.isNotEmpty() && s.banner.isEmpty()) { font.data.setScale(1.0f * u); layout.setText(font, s.message); look.outlined(batch, font, s.message, W / 2 - layout.width / 2, 170f + 20f * u, Color(1f, 0.92f, 0.6f, 1f)); font.data.setScale(u) }
        // round banner
        if (s.banner.isNotEmpty()) {
            val bannerRed = Color(0.78f, 0.06f, 0.05f, 1f)
            val big = s.banner.uppercase()
            font.data.setScale(3.0f * u); layout.setText(font, big); look.outlined(batch, font, big, W / 2 - layout.width / 2, H / 2 + 130f + 20f * u, bannerRed, 3f); font.data.setScale(u)
            if (s.message.isNotEmpty()) { font.data.setScale(1.0f * u); layout.setText(font, s.message); look.outlined(batch, font, s.message, W / 2 - layout.width / 2, H / 2 + 60f, Color.WHITE); font.data.setScale(u) }
        }
        if (me != null && me.downed && !s.gameOver) { font.data.setScale(1.3f * u); val t = "YOU ARE DOWN - a teammate can revive you"; layout.setText(font, t); look.outlined(batch, font, t, W / 2 - layout.width / 2, 210f, Color(0.9f, 0.2f, 0.2f, 1f)); font.data.setScale(u) }
        if (s.gameOver) { font.data.setScale(1.1f * u); val t = if (host != null) "Tap / Enter to restart" else "Waiting for host to restart"; layout.setText(font, t); look.outlined(batch, font, t, W / 2 - layout.width / 2, H / 2 + 20f, Color.WHITE); font.data.setScale(u) }
        if (client != null && !client.connected) { font.data.setScale(1.2f * u); val t = "Disconnected from host. Tap to go back."; layout.setText(font, t); look.outlined(batch, font, t, W / 2 - layout.width / 2, H / 2 - 60f, Color.RED); font.data.setScale(u) }
        if (isTouch) { font.data.setScale(0.9f * u); label("USE", useBtn); label(if (me == null || me.abilityCd <= 0f) "SKILL" else me.abilityCd.toInt().toString(), abilityBtn); font.data.setScale(u) }
        batch.end()
    }

    private val layout = GlyphLayout()
    private fun label(t: String, c: Vector2) { layout.setText(font, t); font.draw(batch, t, c.x - layout.width / 2, c.y + layout.height / 2) }

    override fun dispose() {
        if (disposed) return
        disposed = true
        shapes.dispose(); batch.dispose(); font.dispose(); look.dispose()
        host?.close(); client?.close(); (mode as? Mode.Host)?.onClose?.invoke()
    }
}
