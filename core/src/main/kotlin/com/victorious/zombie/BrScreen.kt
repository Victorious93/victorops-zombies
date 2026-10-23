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
import com.badlogic.gdx.math.Vector2
import com.badlogic.gdx.math.Vector3
import com.badlogic.gdx.utils.viewport.FitViewport
import com.victorious.zombie.br.*
import com.victorious.zombie.logic.Character
import com.victorious.zombie.logic.Characters
import com.victorious.zombie.net.HostSession
import com.victorious.zombie.sim.PlayerInput
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Blackout Royale screen. Solo and Host run a [BrWorld] locally; Client renders what the host sends.
 * Twin-stick controls: left stick / WASD moves, right stick or mouse aims and fires. Procedural placeholder visuals.
 */
class BrScreen(private val character: Character = Characters.DEFAULT, private val mode: Mode = Mode.Solo) : ScreenAdapter() {
    private val W = 1280f; private val H = 720f
    private val cam = OrthographicCamera(); private val view = FitViewport(W, H, cam)
    private val hudCam = OrthographicCamera(); private val hudView = FitViewport(W, H, hudCam)
    private val shapes = ShapeRenderer(); private val batch = SpriteBatch(); private val font = BitmapFont()
    private val layout = GlyphLayout()
    private val tmp3 = Vector3()

    private val host: HostSession? = when (mode) {
        is Mode.Solo -> { BrPrefs.load(); HostSession.createRoyale(character, squadSize = BrPrefs.squadSize) }
        is Mode.Host -> mode.session
        is Mode.Client -> null
    }
    private val world: BrWorld? get() = host?.sim as? BrWorld
    private val client = (mode as? Mode.Client)?.session

    // ---- input state
    private val isTouch = Gdx.app.type == Application.ApplicationType.Android || System.getProperty("zombie.touch") == "1" // the property lets the desktop harness draw the phone HUD
    /** Text scale. The default font is ~1 mm tall on a 6-inch phone at this virtual size, so touch devices get bigger type. */
    private val ui = if (isTouch) 1.6f else 1f
    init { font.data.setScale(ui) }
    private val moveC = Vector2(150f, 150f); private val aimC = Vector2(W - 170f, 150f)
    private val useB = Vector2(W - 95f, 330f); private val healB = Vector2(W - 205f, 340f); private val skillB = Vector2(W - 325f, 310f); private val reloadB = Vector2(W - 345f, 190f)
    private val squadOpt = floatArrayOf(W / 2 - 270f, 150f, 540f, 62f) // lobby: x, y, w, h (the host taps it to change the squad size)
    private val moveV = Vector2(); private val aimV = Vector2()
    private var aimDir = Vector2(1f, 0f)

    // ---- view state
    private var snap: BrSnapshot? = null
    private var map: BrMap? = null
    private val shown = HashMap<Int, Vector2>()
    private val camPos = Vector2(BrConst.CENTER, BrConst.CENTER); private var camInit = false
    private class Float3(val x: Float, val y: Float, var age: Float, val text: String, val color: Color)
    private val floaters = ArrayList<Float3>()
    private val seenHits = HashSet<Int>()
    private var time = 0f
    private var done = false; private var disposed = false

    override fun resize(width: Int, height: Int) { view.update(width, height, false); hudView.update(width, height, true); hudCam.position.set(W / 2, H / 2, 0f); hudCam.update() }

    override fun render(delta: Float) {
        if (done) return
        val dt = min(delta, 1 / 30f); time += dt
        val s0 = snap
        val input = readInput(s0)
        if (Gdx.input.isKeyJustPressed(Input.Keys.ESCAPE)) { backToMenu(); return }
        if (host != null) { host.sim.applyInput(HostSession.HOST_ID, input); host.tick(dt); snap = world?.snapshot(HostSession.HOST_ID) }
        else if (client != null) { client.tick(dt, input); snap = client.latestRoyale }
        val s = snap
        if (s != null) {
            if (map == null || map!!.seed != s.seed) map = world?.map?.takeIf { it.seed == s.seed } ?: BrMap(s.seed)
            ingestHits(s)
        }
        if (client != null && (!client.connected || client.rejected) && (Gdx.input.justTouched() || Gdx.input.isKeyJustPressed(Input.Keys.ENTER))) { backToMenu(); return }
        updateCamera(s, dt)
        floaters.forEach { it.age += dt }; floaters.removeAll { it.age > 0.9f }
        if (!done) draw(s, dt)
    }

    private fun backToMenu() {
        if (done) return
        done = true
        (Gdx.app.applicationListener as? VictorOpsGame)?.setScreen(CharacterSelectScreen()); dispose()
    }

    // ---- input ----------------------------------------------------------------------------------------------------
    private fun readInput(s: BrSnapshot?): PlayerInput {
        var dx = 0f; var dy = 0f
        val k = Gdx.input
        if (k.isKeyPressed(Input.Keys.W)) dy += 1; if (k.isKeyPressed(Input.Keys.S)) dy -= 1
        if (k.isKeyPressed(Input.Keys.A)) dx -= 1; if (k.isKeyPressed(Input.Keys.D)) dx += 1
        var use = k.isKeyPressed(Input.Keys.E); var ability = k.isKeyPressed(Input.Keys.Q)
        var heal = k.isKeyPressed(Input.Keys.F); var reload = k.isKeyPressed(Input.Keys.R)
        var fire = false; var ax = 0f; var ay = 0f
        val me = s?.fighters?.firstOrNull { it.id == s.meId }

        // mouse aim + fire (desktop)
        if (!isTouch && me != null && me.alive) {
            view.unproject(tmp3.set(k.x.toFloat(), k.y.toFloat(), 0f))
            val p = shown[me.id]
            val ox = p?.x ?: me.x; val oy = p?.y ?: me.y
            val vx = tmp3.x - ox; val vy = tmp3.y - oy; val l = hypot(vx, vy)
            if (l > 6f) { ax = vx / l; ay = vy / l; aimDir.set(ax, ay) } else { ax = aimDir.x; ay = aimDir.y }
            fire = k.isButtonPressed(Input.Buttons.LEFT) || k.isKeyPressed(Input.Keys.SPACE)
        }

        // touch sticks and buttons
        moveV.setZero(); aimV.setZero()
        var moveActive = false; var aimActive = false
        if (isTouch) {
            use = false; ability = false; heal = false; reload = false
            for (p in 0 until 5) {
                if (!k.isTouched(p)) continue
                hudView.unproject(tmp3.set(k.getX(p).toFloat(), k.getY(p).toFloat(), 0f))
                val x = tmp3.x; val y = tmp3.y
                when {
                    x < W / 2 -> { moveV.set(x - moveC.x, y - moveC.y).limit(90f); moveActive = true }
                    Vector2.dst(x, y, useB.x, useB.y) < 50f -> use = true
                    Vector2.dst(x, y, healB.x, healB.y) < 50f -> heal = true
                    Vector2.dst(x, y, skillB.x, skillB.y) < 50f -> ability = true
                    Vector2.dst(x, y, reloadB.x, reloadB.y) < 46f -> reload = true
                    else -> { aimV.set(x - aimC.x, y - aimC.y).limit(90f); aimActive = true }
                }
            }
            if (moveActive) { dx = moveV.x / 90f; dy = moveV.y / 90f }
            if (aimActive && aimV.len() > 18f) {
                ax = aimV.x / aimV.len(); ay = aimV.y / aimV.len(); aimDir.set(ax, ay)
                fire = aimV.len() > 32f
                if (fire && me != null) assist(s, me)?.let { ax = it.x; ay = it.y }
            }
        }
        // tap / Enter starts or restarts (host) in the lobby and after a match; in the lobby the squad button and T change the squad size instead
        if (s != null && s.phase == Phase.LOBBY.ordinal && host != null) {
            var cycle = k.isKeyJustPressed(Input.Keys.T); var tapped = k.justTouched()
            if (tapped) { hudView.unproject(tmp3.set(k.x.toFloat(), k.y.toFloat(), 0f)); if (tmp3.x in squadOpt[0]..squadOpt[0] + squadOpt[2] && tmp3.y in squadOpt[1]..squadOpt[1] + squadOpt[3]) { cycle = true; tapped = false } }
            if (cycle) world?.let { BrPrefs.squadSize = BrPrefs.next(it.squadSize); it.setSquadSize(BrPrefs.squadSize) }
            if (tapped || k.isKeyJustPressed(Input.Keys.ENTER)) use = true
        } else if (s != null && s.phase == Phase.ENDED.ordinal && host != null && (k.justTouched() || k.isKeyJustPressed(Input.Keys.ENTER))) use = true
        return PlayerInput(dx, dy, use, ability, ax, ay, fire, heal, reload)
    }

    /** Small touch aim assist: snap to the enemy closest to the stick direction when it is within ~10 degrees. */
    private fun assist(s: BrSnapshot?, me: BrFighterSnap): Vector2? {
        if (s == null) return null
        val range = BrGuns.at(me.gunIndex).range
        var best: Vector2? = null; var bestOff = 10f * PI.toFloat() / 180f
        val cur = atan2(aimDir.y, aimDir.x)
        fun consider(x: Float, y: Float) {
            val d = hypot(x - me.x, y - me.y); if (d > range || d < 1f) return
            val off = abs(angleDiff(cur, atan2(y - me.y, x - me.x)))
            if (off < bestOff) { bestOff = off; best = Vector2((x - me.x) / d, (y - me.y) / d) }
        }
        s.fighters.forEach { if (it.id != me.id && it.alive && !(s.squadSize > 1 && it.squad == me.squad)) consider(it.x, it.y) }
        s.zombies.forEach { consider(it.x, it.y) }
        return best
    }

    private fun angleDiff(a: Float, b: Float): Float { var d = (b - a) % (2 * PI.toFloat()); if (d > PI) d -= 2 * PI.toFloat(); if (d < -PI) d += 2 * PI.toFloat(); return d }

    // ---- state helpers --------------------------------------------------------------------------------------------
    private fun ingestHits(s: BrSnapshot) {
        for (h in s.hits) {
            if (!seenHits.add(h.seq)) continue
            floaters += Float3(h.x, h.y, 0f, if (h.kill && h.mine) "${h.amount}!" else "${h.amount}", if (h.hurt) Color(1f, 0.3f, 0.3f, 1f) else Color(1f, 0.9f, 0.3f, 1f))
        }
        if (seenHits.size > 400) seenHits.clear()
    }

    private fun smooth(key: Int, x: Float, y: Float, dt: Float): Vector2 {
        if (client == null) return shown.getOrPut(key) { Vector2() }.set(x, y)
        if (shown.size > 600) shown.clear()
        val v = shown.getOrPut(key) { Vector2(x, y) }
        if (hypot(x - v.x, y - v.y) > 300f) v.set(x, y)
        val k = 1f - exp((-18f * dt).toDouble()).toFloat()
        v.x += (x - v.x) * k; v.y += (y - v.y) * k
        return v
    }

    private fun updateCamera(s: BrSnapshot?, dt: Float) {
        if (s == null) return
        val target = Vector2(s.camX, s.camY)
        if (!camInit || camPos.dst(target) > 500f) { camPos.set(target); camInit = true }
        val k = 1f - exp((-12f * dt).toDouble()).toFloat()
        camPos.x += (target.x - camPos.x) * k; camPos.y += (target.y - camPos.y) * k
        cam.position.set(camPos.x.coerceIn(W / 2 - 60f, BrConst.SIZE - W / 2 + 60f), camPos.y.coerceIn(H / 2 - 60f, BrConst.SIZE - H / 2 + 60f), 0f)
        cam.update()
    }

    private fun gunColor(r: Int) = when (r) { 2 -> Color(0.78f, 0.38f, 1f, 1f); 1 -> Color(0.3f, 0.65f, 1f, 1f); else -> Color(0.82f, 0.82f, 0.85f, 1f) }
    private val fighterColors = listOf(Color(0.1f, 0.95f, 1f, 1f), Color(1f, 0.6f, 0.2f, 1f), Color(0.5f, 1f, 0.4f, 1f), Color(1f, 0.4f, 0.9f, 1f), Color(1f, 0.85f, 0.3f, 1f), Color(0.6f, 0.6f, 1f, 1f))
    private fun colorOf(id: Int) = fighterColors[id % fighterColors.size]
    /** Squad rings: my own squad is always green, the others get a colour each. */
    private val squadColors = listOf(Color(1f, 0.62f, 0.15f, 1f), Color(1f, 0.3f, 0.8f, 1f), Color(1f, 0.92f, 0.2f, 1f), Color(0.45f, 0.65f, 1f, 1f), Color(1f, 0.4f, 0.4f, 1f), Color(0.7f, 0.5f, 1f, 1f))
    private val mySquadColor = Color(0.3f, 1f, 0.45f, 1f)
    private fun squadColor(sq: Int, mine: Int) = if (sq == mine) mySquadColor else squadColors[(if (sq > mine) sq - 1 else sq) % squadColors.size]

    /** Starts a shape pass with alpha blending on: [SpriteBatch.end] switches blending off, which made every translucent shape drawn after text opaque. */
    private fun beginShapes(type: ShapeRenderer.ShapeType) {
        Gdx.gl.glEnable(GL20.GL_BLEND); Gdx.gl.glBlendFunc(GL20.GL_SRC_ALPHA, GL20.GL_ONE_MINUS_SRC_ALPHA)
        shapes.begin(type)
    }

    // ---- drawing --------------------------------------------------------------------------------------------------
    private fun draw(s: BrSnapshot?, dt: Float) {
        Gdx.gl.glClearColor(0.02f, 0.02f, 0.04f, 1f); Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT)
        Gdx.gl.glEnable(GL20.GL_BLEND); Gdx.gl.glBlendFunc(GL20.GL_SRC_ALPHA, GL20.GL_ONE_MINUS_SRC_ALPHA)
        if (s == null) {
            hudView.apply(); batch.projectionMatrix = hudCam.combined; batch.begin(); font.color = Color.WHITE
            text(if (client != null && (!client.connected || client.rejected)) "Could not join (host full, in progress or gone). Tap to go back." else "Connecting...", W / 2, H / 2, 1.2f)
            batch.end(); return
        }
        val m = map
        val me = s.fighters.firstOrNull { it.id == s.meId }
        val phase = Phase.values()[s.phase.coerceIn(0, 3)]
        if (phase == Phase.LOBBY) { // a clean screen: nothing of the arena exists yet
            hudView.apply(); shapes.projectionMatrix = hudCam.combined; batch.projectionMatrix = hudCam.combined
            beginShapes(ShapeRenderer.ShapeType.Line); shapes.color = Color(1f, 0.35f, 0.5f, 0.35f)
            for (r in 1..4) shapes.circle(W / 2, H / 2 - 40f, r * 90f, 64)
            shapes.end()
            lobbyButton(s)
            batch.begin(); font.color = Color.WHITE; lobbyText(s); batch.end()
            if (client != null && !client.connected) { batch.begin(); font.color = Color.RED; text("Disconnected from host. Tap to go back.", W / 2, H / 2 - 60f, 1.2f); batch.end() }
            return
        }
        view.apply()
        shapes.projectionMatrix = cam.combined; batch.projectionMatrix = cam.combined
        val x0 = cam.position.x - W / 2 - 60f; val x1 = cam.position.x + W / 2 + 60f; val y0 = cam.position.y - H / 2 - 60f; val y1 = cam.position.y + H / 2 + 60f

        // world, filled
        beginShapes(ShapeRenderer.ShapeType.Filled)
        shapes.color = Color(0.085f, 0.095f, 0.12f, 1f); shapes.rect(0f, 0f, BrConst.SIZE, BrConst.SIZE)
        m?.pois?.forEach { shapes.color = Color(0.11f, 0.12f, 0.16f, 1f); shapes.circle(it.x, it.y, 330f, 40) }
        shapes.color = Color(0.12f, 0.13f, 0.17f, 1f)
        var g = (x0 / 200f).toInt().coerceAtLeast(0) * 200f; while (g < min(x1, BrConst.SIZE)) { shapes.rect(g, max(0f, y0), 1.5f, min(y1, BrConst.SIZE) - max(0f, y0)); g += 200f }
        g = (y0 / 200f).toInt().coerceAtLeast(0) * 200f; while (g < min(y1, BrConst.SIZE)) { shapes.rect(max(0f, x0), g, min(x1, BrConst.SIZE) - max(0f, x0), 1.5f); g += 200f }
        m?.walls?.forEach { if (it.x2 >= x0 && it.x <= x1 && it.y2 >= y0 && it.y <= y1) { shapes.color = Color(0.3f, 0.32f, 0.4f, 1f); shapes.rect(it.x, it.y, it.w, it.h); shapes.color = Color(0.42f, 0.44f, 0.54f, 1f); shapes.rect(it.x + 2, it.y + it.h - 4, it.w - 4, 3f) } }
        for (l in s.loot) {
            when (l.kind) {
                0 -> { shapes.color = gunColor(l.rarity); shapes.rect(l.x - 12, l.y - 6, 24f, 12f); shapes.color = Color(0.1f, 0.1f, 0.12f, 1f); shapes.rect(l.x - 9, l.y - 3, 18f, 6f) }
                1 -> { shapes.color = Color(0.95f, 0.2f, 0.25f, 1f); shapes.rect(l.x - 9, l.y - 9, 18f, 18f); shapes.color = Color.WHITE; shapes.rect(l.x - 6, l.y - 2, 12f, 4f); shapes.rect(l.x - 2, l.y - 6, 4f, 12f) }
                else -> { shapes.color = Color(0.3f, 0.7f, 1f, 1f); shapes.rect(l.x - 8, l.y - 8, 16f, 16f); shapes.color = Color(0.7f, 0.9f, 1f, 1f); shapes.rect(l.x - 4, l.y - 4, 8f, 8f) }
            }
        }
        for (a in s.airdrops) {
            val fall = (a.t / BrWorld.AIRDROP_FALL).coerceIn(0f, 1f)
            shapes.color = Color(1f, 0.8f, 0.2f, 0.5f); shapes.rect(a.x - 3, a.y, 6f, 60f * fall + 14f)
            shapes.color = Color(0.85f, 0.65f, 0.2f, 1f); shapes.rect(a.x - 16, a.y + 60f * fall, 32f, 24f)
        }
        s.zombies.forEach { val p = smooth(it.id + 10_000, it.x, it.y, dt); shapes.color = Color(0.35f, 0.75f, 0.3f, 1f); shapes.circle(p.x, p.y, BrConst.ZOMBIE_R) }
        s.bullets.forEach {
            shapes.color = Color(1f, 0.95f, 0.5f, 0.45f); shapes.rectLine(it.x, it.y, it.x - cos(it.angle) * 16f, it.y - sin(it.angle) * 16f, 2f)
            shapes.color = Color(1f, 0.95f, 0.5f, 1f); shapes.circle(it.x, it.y, 3f)
        }
        val squads = s.squadSize > 1
        val mySquad = me?.squad ?: -1
        for (f in s.fighters) {
            if (!f.alive) continue
            val p = smooth(f.id, f.x, f.y, dt)
            if (squads) { // squad ring: a solid halo under the body (thin outlines vanish on a phone)
                if (f.downed) { // revive clock: a dark disc with a green wedge that fills as the mate works
                    shapes.color = Color(0f, 0f, 0f, 0.55f); shapes.circle(p.x, p.y, BrConst.BODY_R + 15f, 24)
                    if (f.reviveP > 0.01f) { shapes.color = Color(0.4f, 1f, 0.5f, 0.95f); shapes.arc(p.x, p.y, BrConst.BODY_R + 15f, 90f, -360f * f.reviveP, 24) }
                }
                shapes.color = squadColor(f.squad, mySquad); shapes.circle(p.x, p.y, BrConst.BODY_R + 5f, 20)
            }
            val base = if (f.id == s.meId) Color(0.1f, 0.95f, 1f, 1f) else colorOf(f.id)
            shapes.color = if (f.downed) Color(base.r * 0.45f + 0.15f, base.g * 0.45f + 0.15f, base.b * 0.45f + 0.15f, 1f) else base
            shapes.circle(p.x, p.y, BrConst.BODY_R)
            if (f.downed) { // red cross: "needs help"
                shapes.color = Color(1f, 0.15f, 0.2f, 1f); shapes.rect(p.x - 8f, p.y - 2.5f, 16f, 5f); shapes.rect(p.x - 2.5f, p.y - 8f, 5f, 16f)
            } else {
                shapes.color = Color(0.1f, 0.1f, 0.12f, 1f); shapes.rectLine(p.x, p.y, p.x + cos(f.aim) * 24f, p.y + sin(f.aim) * 24f, 5f)
                shapes.color = gunColor(f.rarity); shapes.rectLine(p.x + cos(f.aim) * 10f, p.y + sin(f.aim) * 10f, p.x + cos(f.aim) * 22f, p.y + sin(f.aim) * 22f, 3f)
            }
            // bars (a downed fighter shows the bleed-out clock instead of health)
            shapes.color = Color(0f, 0f, 0f, 0.6f); shapes.rect(p.x - 17, p.y + 21, 34f, 9f)
            if (f.downed) { shapes.color = Color(1f, 0.55f, 0.1f, 1f); shapes.rect(p.x - 16, p.y + 22, 32f * f.bleed.coerceIn(0f, 1f), 7f) }
            else {
                shapes.color = Color(0.9f, 0.2f, 0.25f, 1f); shapes.rect(p.x - 16, p.y + 22, 32f * (f.hp / f.maxHp).coerceIn(0f, 1f), 3f)
                shapes.color = Color(0.3f, 0.7f, 1f, 1f); shapes.rect(p.x - 16, p.y + 26, 32f * (f.shield / BrWorld.MAX_SHIELD).coerceIn(0f, 1f), 3f)
            }
            if (f.reloading) { shapes.color = Color(1f, 1f, 1f, 0.7f); shapes.rect(p.x - 10, p.y - 22, 20f, 2f) }
            if (f.healing) { shapes.color = Color(0.4f, 1f, 0.5f, 0.9f); shapes.rect(p.x - 10, p.y - 26, 20f, 2f) }
        }
        shapes.end()

        // zone: danger overlay outside the safe circle (triangle ring) + outlines
        drawZone(s.zone)

        // damage numbers and names (world space text)
        batch.begin(); font.color = Color.WHITE
        m?.pois?.forEach { font.color = Color(1f, 1f, 1f, 0.22f); font.data.setScale(2f * ui); layout.setText(font, it.name); font.draw(batch, it.name, it.x - layout.width / 2, it.y + 12); font.data.setScale(ui) }
        for (f in s.fighters) {
            if (!f.alive || f.id == s.meId) continue
            val p = smooth(f.id, f.x, f.y, dt)
            val mate = s.squadSize > 1 && f.squad == me?.squad
            font.color = if (mate) mySquadColor else Color(1f, 1f, 1f, 0.85f)
            val label = if (f.downed) "${f.name}  DOWN" else f.name
            layout.setText(font, label); font.draw(batch, label, p.x - layout.width / 2, p.y + 44)
        }
        for (a in s.airdrops) { font.color = Color(1f, 0.85f, 0.3f, 1f); font.draw(batch, "SUPPLY ${max(0, a.t.toInt())}s", a.x - 34, a.y - 8) }
        for (f in floaters) { val k = f.age / 0.9f; font.color = Color(f.color.r, f.color.g, f.color.b, 1f - k * k); font.data.setScale(1.2f * ui); font.draw(batch, f.text, f.x - 8, f.y + 30 + 40 * k); font.data.setScale(ui) }
        batch.end()

        // aim line + zone arrow (line type)
        beginShapes(ShapeRenderer.ShapeType.Line)
        if (me != null && me.alive && phase == Phase.LIVE) {
            val p = smooth(me.id, me.x, me.y, dt)
            val range = BrGuns.at(me.gunIndex).range
            shapes.color = Color(1f, 1f, 1f, 0.12f); shapes.line(p.x, p.y, p.x + cos(me.aim) * min(range, 420f), p.y + sin(me.aim) * min(range, 420f))
            if (hypot(p.x - s.zone.cx, p.y - s.zone.cy) > s.zone.r) {
                val a = atan2(s.zone.cy - p.y, s.zone.cx - p.x)
                shapes.color = Color(1f, 0.3f, 0.3f, 1f)
                val ex = p.x + cos(a) * 70f; val ey = p.y + sin(a) * 70f
                shapes.line(p.x + cos(a) * 30f, p.y + sin(a) * 30f, ex, ey); shapes.line(ex, ey, ex - cos(a - 0.5f) * 14f, ey - sin(a - 0.5f) * 14f); shapes.line(ex, ey, ex - cos(a + 0.5f) * 14f, ey - sin(a + 0.5f) * 14f)
            }
        }
        for (f in s.fighters) if (f.alive && f.reviving) { val p = smooth(f.id, f.x, f.y, dt); shapes.color = Color(0.4f, 1f, 0.5f, 0.6f + 0.4f * sin(time * 10f)); shapes.circle(p.x, p.y, BrConst.BODY_R + 9f, 24) }
        for (f in s.fighters) if (f.alive && (f.protectedNow || f.reduced)) { val p = smooth(f.id, f.x, f.y, dt); shapes.color = if (f.reduced) Color(0.4f, 0.8f, 1f, 1f) else Color(1f, 1f, 1f, 0.6f + 0.4f * sin(time * 8f)); shapes.circle(p.x, p.y, BrConst.BODY_R + 5f, 24) }
        shapes.end()

        drawHud(s, me, phase, dt)
    }

    private fun drawZone(z: BrZoneSnap) {
        beginShapes(ShapeRenderer.ShapeType.Filled)
        shapes.color = Color(0.7f, 0.05f, 0.25f, 0.3f)
        val seg = 96; val outer = 3600f
        for (i in 0 until seg) {
            val a0 = i * 2 * PI.toFloat() / seg; val a1 = (i + 1) * 2 * PI.toFloat() / seg
            val ix0 = z.cx + cos(a0) * z.r; val iy0 = z.cy + sin(a0) * z.r; val ix1 = z.cx + cos(a1) * z.r; val iy1 = z.cy + sin(a1) * z.r
            val ox0 = z.cx + cos(a0) * outer; val oy0 = z.cy + sin(a0) * outer; val ox1 = z.cx + cos(a1) * outer; val oy1 = z.cy + sin(a1) * outer
            shapes.triangle(ix0, iy0, ox0, oy0, ox1, oy1); shapes.triangle(ix0, iy0, ox1, oy1, ix1, iy1)
        }
        shapes.end()
        beginShapes(ShapeRenderer.ShapeType.Line)
        shapes.color = Color(1f, 0.35f, 0.5f, 1f); shapes.circle(z.cx, z.cy, z.r, 120)
        if (z.nextR > 0f && (z.nextCx != z.cx || z.nextR != z.r)) { shapes.color = Color(1f, 1f, 1f, 0.7f); shapes.circle(z.nextCx, z.nextCy, z.nextR, 90) }
        shapes.end()
    }

    private fun drawHud(s: BrSnapshot, me: BrFighterSnap?, phase: Phase, dt: Float) {
        hudView.apply()
        shapes.projectionMatrix = hudCam.combined; batch.projectionMatrix = hudCam.combined
        val self = s.self
        // minimap
        val mm = 170f; val mx = W - mm - 16f; val my = H - mm - 16f; val sc = mm / BrConst.SIZE
        beginShapes(ShapeRenderer.ShapeType.Filled)
        shapes.color = Color(0f, 0f, 0f, 0.55f); shapes.rect(mx, my, mm, mm)
        map?.pois?.forEach { shapes.color = Color(0.2f, 0.22f, 0.3f, 1f); shapes.circle(mx + it.x * sc, my + it.y * sc, 330f * sc, 16) }
        s.airdrops.forEach { shapes.color = Color(1f, 0.8f, 0.2f, 1f); shapes.rect(mx + it.x * sc - 2, my + it.y * sc - 2, 4f, 4f) }
        val mateColor = Color(0.3f, 1f, 0.45f, 1f)
        s.fighters.forEach {
            if (it.alive) {
                val mate = s.squadSize > 1 && it.id != s.meId && it.squad == me?.squad
                shapes.color = if (it.id == s.meId) Color(0.1f, 0.95f, 1f, 1f) else if (mate) (if (it.downed) Color(1f, 0.6f, 0.1f, 1f) else mateColor) else Color(1f, 0.4f, 0.4f, 1f)
                shapes.circle(mx + it.x * sc, my + it.y * sc, if (it.id == s.meId) 3.5f else if (mate) 3f else 2.2f)
            }
        }
        if (me == null || !me.alive) { shapes.color = Color.WHITE; shapes.circle(mx + s.camX * sc, my + s.camY * sc, 3f) }
        if (phase == Phase.LIVE || phase == Phase.DEPLOY) {
            // bars
            shapes.color = Color(0f, 0f, 0f, 0.55f); shapes.rect(18f, H - 50f, 244f, 34f)
            if (me != null) {
                shapes.color = Color(0.9f, 0.2f, 0.25f, 1f); shapes.rect(22f, H - 36f, 236f * (me.hp / me.maxHp).coerceIn(0f, 1f), 14f)
                shapes.color = Color(0.3f, 0.7f, 1f, 1f); shapes.rect(22f, H - 46f, 236f * (me.shield / BrWorld.MAX_SHIELD).coerceIn(0f, 1f), 7f)
            }
            if (self != null && self.healProgress > 0f) { shapes.color = Color(0.4f, 1f, 0.5f, 0.9f); shapes.rect(W / 2 - 60, 150f, 120f * self.healProgress, 6f) }
            if (self != null && phase == Phase.LIVE && s.squadSize > 1) drawSquadShapes(s, me, self)
        }
        if (isTouch && phase == Phase.LIVE) {
            shapes.color = Color(1f, 1f, 1f, 0.12f); shapes.circle(moveC.x, moveC.y, 90f); shapes.circle(aimC.x, aimC.y, 90f)
            shapes.color = Color(0.1f, 0.95f, 1f, 0.45f); shapes.circle(moveC.x + moveV.x, moveC.y + moveV.y, 34f)
            shapes.color = Color(1f, 0.5f, 0.2f, if (aimV.len() > 32f) 0.65f else 0.35f); shapes.circle(aimC.x + aimV.x, aimC.y + aimV.y, 34f)
            val reviveHint = self != null && (self.prompt.startsWith("REVIVE") || self.reviveProgress > 0.01f && !self.downed)
            shapes.color = if (reviveHint) Color(0.4f, 1f, 0.5f, 0.55f + 0.3f * sin(time * 8f)) else Color(1f, 0.15f, 0.85f, 0.35f); shapes.circle(useB.x, useB.y, if (reviveHint) 46f else 40f)
            shapes.color = Color(0.4f, 1f, 0.5f, 0.35f); shapes.circle(healB.x, healB.y, 40f)
            shapes.color = Color(1f, 0.8f, 0.1f, if (self != null && self.abilityCd <= 0f) 0.5f else 0.15f); shapes.circle(skillB.x, skillB.y, 42f)
            shapes.color = Color(1f, 1f, 1f, 0.25f); shapes.circle(reloadB.x, reloadB.y, 34f)
        }
        shapes.end()
        beginShapes(ShapeRenderer.ShapeType.Line)
        shapes.color = Color(1f, 1f, 1f, 0.5f); shapes.rect(mx, my, mm, mm)
        shapes.color = Color(1f, 0.35f, 0.5f, 1f); shapes.circle(mx + s.zone.cx * sc, my + s.zone.cy * sc, s.zone.r * sc, 48)
        if (s.zone.nextR > 0f) { shapes.color = Color.WHITE; shapes.circle(mx + s.zone.nextCx * sc, my + s.zone.nextCy * sc, s.zone.nextR * sc, 36) }
        shapes.end()

        batch.begin(); font.color = Color.WHITE
        when (phase) {
            Phase.LOBBY -> lobbyText(s)
            Phase.DEPLOY -> {}
            Phase.LIVE, Phase.ENDED -> {}
        }
        if (phase == Phase.LIVE || phase == Phase.DEPLOY) {
            if (me != null) {
                val gun = BrGuns.at(me.gunIndex); val rar = Rarity.values()[me.rarity.coerceIn(0, 2)]
                font.color = gunColor(me.rarity)
                font.draw(batch, (if (rar == Rarity.COMMON) gun.name else "${rar.label} ${gun.name}") + "   " + (if (me.reloading) "RELOADING" else "${me.rounds}/${self?.magSize ?: 0}"), 22f, H - 58f)
                font.color = Color.WHITE
                font.draw(batch, "HP ${me.hp.toInt()}   SHIELD ${me.shield.toInt()}", 22f, H - 58f - lh)
            }
            if (self != null) {
                font.draw(batch, "MEDKIT x${self.medkits}   CELL x${self.cells}   KILLS ${self.kills}", 22f, H - 58f - 2 * lh)
                font.draw(batch, characterAbility(me) + if (self.abilityCd <= 0f) ": READY [Q]" else ": ${self.abilityCd.toInt()}s", 22f, H - 58f - 3 * lh)
            }
            text(if (s.squadSize > 1) "SQUADS ${s.squadsAlive}   ALIVE ${s.alive}" else "ALIVE ${s.alive}", W / 2, H - 18f, 1.5f)
            val zl = if (s.zone.stage >= BrWorld.ZONES.size) "FINAL ZONE" else if (s.zone.shrinking) "ZONE CLOSING  ${s.zone.timeLeft.toInt()}s" else "NEXT ZONE IN  ${s.zone.timeLeft.toInt()}s"
            text(zl, W / 2, H - 24f - 22.5f * ui, 1f)
            if (me != null && me.alive && hypot(me.x - s.zone.cx, me.y - s.zone.cy) > s.zone.r) { font.color = Color(1f, 0.35f, 0.4f, 1f); text("IN THE DEAD ZONE  -${s.zone.dps.toInt()}/s  GET INSIDE", W / 2, 190f, 1.2f); font.color = Color.WHITE }
            if (self != null && self.prompt.isNotEmpty()) {
                val hold = self.prompt.startsWith("REVIVE")
                if (hold) font.color = Color(0.4f, 1f, 0.5f, 1f)
                text(self.prompt + if (hold) (if (isTouch) "  (hold USE)" else "  (hold E)") else if (isTouch) "  (tap USE)" else "  (press E)", W / 2, 120f, if (hold) 1.2f else 1f); font.color = Color.WHITE
            }
            if (self != null && !self.alive) { font.color = Color(1f, 0.5f, 0.5f, 1f); text((if (s.squadSize > 1) "SQUAD OUT  -  #${self.placement}" else "ELIMINATED  -  #${self.placement}") + "   spectating ${self.spectating}", W / 2, 150f, 1.2f); font.color = Color.WHITE }
            if (self != null && phase == Phase.LIVE && s.squadSize > 1) drawSquadText(s, me, self)
            var fy = H - mm - 30f
            font.data.setScale(0.9f * ui); for (line in s.feed.asReversed()) { layout.setText(font, line); font.draw(batch, line, W - 16f - layout.width, fy); fy -= 16f * ui }; font.data.setScale(ui)
            if (isTouch) { label("USE", useB); label("HEAL", healB); label(if (self == null || self.abilityCd <= 0f) "SKILL" else self.abilityCd.toInt().toString(), skillB); label("R", reloadB) }
        }
        if (s.banner.isNotEmpty() && phase != Phase.ENDED) { font.color = Color(1f, 0.9f, 0.4f, 1f); text(s.banner, W / 2, H / 2 + 150f, 2f); font.color = Color.WHITE }
        if (phase == Phase.ENDED) resultText(s, self)
        if (client != null && !client.connected) { font.color = Color.RED; text("Disconnected from host. Tap to go back.", W / 2, H / 2 - 60f, 1.2f); font.color = Color.WHITE }
        batch.end()
    }

    private fun characterAbility(me: BrFighterSnap?) = (me?.let { Characters.byId(it.characterId).abilityName }) ?: character.abilityName

    private val lh get() = 18f * ui

    /** Draws a centred line at [y] and returns the y for the next line, [gap] below its bottom edge. */
    private fun line(t: String, y: Float, scale: Float, gap: Float = 12f): Float { text(t, W / 2, y, scale); return y - 15f * scale * ui - gap }

    private fun lobbyText(s: BrSnapshot) {
        var y = H - 70f
        font.color = Color(1f, 0.9f, 0.4f, 1f); y = line("BLACKOUT ROYALE", y, 3f, 18f); font.color = Color.WHITE
        y = line("${s.field} fighters  -  last one standing wins. Stay inside the Dead Zone.", y, 1.1f, 30f)
        y = line("Players", y, 1.2f, 8f)
        s.lobby.forEachIndexed { i, n -> y = line(if (s.squadSize > 1) "Squad ${i / s.squadSize + 1}   $n" else n, y, 1f, 6f) }
        y -= 14f
        line(if (host != null) "Bots fill the rest. Starts in ${s.timer.toInt()}s  -  ${if (isTouch) "tap" else "press Enter / tap"} to start now" else "Waiting for the host to start...  (${s.timer.toInt()}s)", y, 1.2f)
        if (!isTouch) text("WASD move   Mouse aim   Click fire   E swap gun / hold to revive   F heal (hold)   Q skill   R reload   Esc leave", W / 2, 70f, 0.95f)
        if (s.squadSize > 1) text("Hold USE next to a downed squad mate to revive them. Mates cannot hurt each other.", W / 2, 118f, 0.95f)
        val label = BrPrefs.label(s.squadSize, s.field) + if (host != null) "   (${if (isTouch) "tap" else "T / click"} to change)" else ""
        text(label, W / 2, squadOpt[1] + squadOpt[3] / 2 + 8f * ui, 1.2f)
    }

    /** Lobby button background (drawn with the shapes before the text). */
    private fun lobbyButton(s: BrSnapshot) {
        if (host == null) return
        beginShapes(ShapeRenderer.ShapeType.Filled)
        shapes.color = if (s.squadSize > 1) Color(0.08f, 0.34f, 0.26f, 0.95f) else Color(0.2f, 0.2f, 0.26f, 0.95f)
        shapes.rect(squadOpt[0], squadOpt[1], squadOpt[2], squadOpt[3])
        shapes.end()
    }

    private fun squadMates(s: BrSnapshot, me: BrFighterSnap?) = if (me == null) emptyList() else s.fighters.filter { it.squad == me.squad && it.id != me.id }

    private val squadRowH get() = 1.25f * lh
    private val squadTop get() = H - 58f - 4 * lh - 14f

    /** Squad panel bars, edge arrows to downed mates, and the downed overlay (shapes; the text goes with [drawSquadText]). */
    private fun drawSquadShapes(s: BrSnapshot, me: BrFighterSnap?, self: BrSelf) {
        val mates = squadMates(s, me)
        val barX = 22f + 78f * ui
        mates.forEachIndexed { i, m ->
            val top = squadTop - i * squadRowH
            shapes.color = Color(0f, 0f, 0f, 0.55f); shapes.rect(14f, top - squadRowH + 2f, 214f + 156f * ui, squadRowH - 2f)
            shapes.color = mySquadColor; shapes.rect(18f, top - squadRowH + 6f, 5f, squadRowH - 10f)
            if (!m.alive) return@forEachIndexed
            if (m.downed) {
                shapes.color = Color(0.25f, 0.1f, 0.05f, 1f); shapes.rect(barX, top - 0.8f * lh, 100f, 9f)
                shapes.color = Color(1f, 0.55f, 0.1f, 1f); shapes.rect(barX, top - 0.8f * lh, 100f * m.bleed.coerceIn(0f, 1f), 9f)
                if (m.reviveP > 0.01f) { shapes.color = Color(0.4f, 1f, 0.5f, 1f); shapes.rect(barX, top - 0.8f * lh - 6f, 100f * m.reviveP, 4f) }
            } else {
                shapes.color = Color(0.25f, 0.06f, 0.08f, 1f); shapes.rect(barX, top - 0.8f * lh, 100f, 9f)
                shapes.color = Color(0.9f, 0.2f, 0.25f, 1f); shapes.rect(barX, top - 0.8f * lh, 100f * (m.hp / m.maxHp).coerceIn(0f, 1f), 9f)
                shapes.color = Color(0.3f, 0.7f, 1f, 1f); shapes.rect(barX, top - 0.8f * lh - 6f, 100f * (m.shield / BrWorld.MAX_SHIELD).coerceIn(0f, 1f), 4f)
            }
        }
        // arrows at the screen edge toward downed mates who are off screen (a phone shows little of the map)
        for (m in mates) if (m.alive && m.downed) {
            val sx = W / 2 + (m.x - cam.position.x); val sy = H / 2 + (m.y - cam.position.y)
            if (sx in 40f..W - 40f && sy in 40f..H - 40f) continue
            val a = atan2(sy - H / 2, sx - W / 2)
            val k = min((W / 2 - 34f) / max(0.001f, abs(cos(a))), (H / 2 - 34f) / max(0.001f, abs(sin(a))))
            val ex = W / 2 + cos(a) * k; val ey = H / 2 + sin(a) * k
            shapes.color = Color(1f, 0.3f, 0.2f, 0.4f + 0.5f * abs(sin(time * 5f)))
            shapes.triangle(ex + cos(a) * 24f, ey + sin(a) * 24f, ex + cos(a + 2.5f) * 20f, ey + sin(a + 2.5f) * 20f, ex + cos(a - 2.5f) * 20f, ey + sin(a - 2.5f) * 20f)
        }
        if (self.downed) { // red wash and the bleed-out clock
            shapes.color = Color(0.6f, 0f, 0.05f, 0.16f); shapes.rect(0f, 0f, W, H)
            shapes.color = Color(0f, 0f, 0f, 0.6f); shapes.rect(W / 2 - 160f, H / 2 + 52f, 320f, 14f)
            shapes.color = Color(1f, 0.55f, 0.1f, 1f); shapes.rect(W / 2 - 158f, H / 2 + 54f, 316f * self.bleed.coerceIn(0f, 1f), 10f)
            if (self.reviveProgress > 0.01f) { shapes.color = Color(0.4f, 1f, 0.5f, 1f); shapes.rect(W / 2 - 158f, H / 2 + 44f, 316f * self.reviveProgress, 6f) }
        } else if (self.reviveProgress > 0.01f) { // my own revive channel
            shapes.color = Color(0f, 0f, 0f, 0.6f); shapes.rect(W / 2 - 100f, 142f, 200f, 14f)
            shapes.color = Color(0.4f, 1f, 0.5f, 1f); shapes.rect(W / 2 - 98f, 144f, 196f * self.reviveProgress, 10f)
        }
    }

    private fun drawSquadText(s: BrSnapshot, me: BrFighterSnap?, self: BrSelf) {
        val mates = squadMates(s, me)
        val barX = 22f + 78f * ui
        font.data.setScale(0.95f * ui)
        mates.forEachIndexed { i, m ->
            val top = squadTop - i * squadRowH
            font.color = if (m.alive) Color.WHITE else Color(0.6f, 0.6f, 0.65f, 1f)
            font.draw(batch, m.name, 28f, top - 4f)
            font.color = if (!m.alive) Color(0.6f, 0.6f, 0.65f, 1f) else if (m.downed) Color(1f, 0.6f, 0.2f, 1f) else Color.WHITE
            val st = if (!m.alive) "OUT" else if (m.downed) (if (m.reviveP > 0.01f) "REVIVING ${(m.reviveP * 100).toInt()}%" else "DOWN ${(m.bleed * BrWorld.BLEED_TIME).toInt()}s") else "${m.hp.toInt()}+${m.shield.toInt()}"
            font.draw(batch, st, barX + 106f, top - 4f)
        }
        font.data.setScale(ui)
        if (self.downed) {
            font.color = Color(1f, 0.4f, 0.35f, 1f); text("YOU ARE DOWN", W / 2, H / 2 + 118f, 2f)
            font.color = Color.WHITE
            text(if (self.reviveProgress > 0.01f) "BEING REVIVED  ${(self.reviveProgress * 100).toInt()}%" else "Bleeding out in ${(self.bleed * BrWorld.BLEED_TIME).toInt()}s  -  a mate can revive you", W / 2, H / 2 + 32f, 1f)
        } else if (self.reviveProgress > 0.01f) {
            font.color = Color(0.4f, 1f, 0.5f, 1f); text("REVIVING ${(self.reviveProgress * 100).toInt()}%", W / 2, 176f, 1.1f); font.color = Color.WHITE
        }
    }

    private fun resultText(s: BrSnapshot, self: BrSelf?) {
        val won = self != null && self.placement == 1
        var y = H / 2 + 190f
        font.color = if (won) Color(1f, 0.9f, 0.3f, 1f) else Color(1f, 0.6f, 0.6f, 1f)
        y = line(if (won) "VICTORY!" else "GAME OVER", y, 3f, 14f)
        font.color = Color.WHITE
        y = line(s.banner, y, 1.3f, 12f)
        if (self != null && s.squadSize > 1) { y = line("Placed #${self.placement} of ${s.squads} squads", y, 1.4f, 10f); y = line("${self.kills} eliminations   -   ${self.squadKills} for the squad", y, 1.1f, 14f) }
        else if (self != null) y = line("Placed #${self.placement} of ${s.field}   -   ${self.kills} eliminations", y, 1.2f, 14f)
        line(if (host != null) "Tap / Enter to play again" else "Waiting for host to restart", y, 1f)
    }

    private fun label(t: String, c: Vector2) { layout.setText(font, t); font.draw(batch, t, c.x - layout.width / 2, c.y + layout.height / 2) }

    /** Draws [t] horizontally centred at [x] with the given scale (resets scale). */
    private fun text(t: String, x: Float, y: Float, scale: Float) {
        font.data.setScale(scale * ui); layout.setText(font, t); font.draw(batch, t, x - layout.width / 2, y); font.data.setScale(ui)
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        shapes.dispose(); batch.dispose(); font.dispose()
        host?.close(); client?.close(); (mode as? Mode.Host)?.onClose?.invoke()
    }
}
