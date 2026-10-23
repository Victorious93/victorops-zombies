package com.victorious.zombie

import com.badlogic.gdx.Application
import com.badlogic.gdx.Gdx
import com.badlogic.gdx.Input
import com.badlogic.gdx.InputAdapter
import com.badlogic.gdx.ScreenAdapter
import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.GL20
import com.badlogic.gdx.graphics.OrthographicCamera
import com.badlogic.gdx.graphics.PerspectiveCamera
import com.badlogic.gdx.graphics.g2d.BitmapFont
import com.badlogic.gdx.graphics.g2d.GlyphLayout
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.badlogic.gdx.graphics.g3d.Environment
import com.badlogic.gdx.graphics.g3d.ModelBatch
import com.badlogic.gdx.graphics.g3d.ModelInstance
import com.badlogic.gdx.graphics.g3d.attributes.ColorAttribute
import com.badlogic.gdx.graphics.g3d.environment.DirectionalLight
import com.badlogic.gdx.graphics.g3d.environment.PointLight
import com.badlogic.gdx.graphics.g3d.model.Node
import com.badlogic.gdx.graphics.g3d.shaders.DefaultShader
import com.badlogic.gdx.graphics.g3d.utils.DefaultShaderProvider
import com.badlogic.gdx.graphics.glutils.ShapeRenderer
import com.badlogic.gdx.math.Matrix4
import com.badlogic.gdx.math.Vector2
import com.badlogic.gdx.math.Vector3
import com.badlogic.gdx.utils.viewport.ExtendViewport
import com.victorious.zombie.fps.*
import com.victorious.zombie.logic.Character
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Zombies 3D: first-person view of an [FpsWorld]. Solo and offline. Touch: left half is a floating move stick, dragging on the
 * right half looks around, FIRE (drag it to aim while shooting), USE, RELOAD, KNIFE, and tap the ammo readout to swap guns.
 * Desktop: WASD, mouse look (click to capture the mouse), left click fire, E use, R reload, V/F knife, Q swap, Esc menu.
 */
class FpsScreen(
    private val character: Character,
    /** Normally a fresh world; the desktop screenshot harness passes a pre-staged one. */
    private val world: FpsWorld = FpsWorld(maxHp = FpsRules.PLAYER_HP * character.maxHealth / 100f, speedMult = character.speedMult),
) : ScreenAdapter() {
    private val p get() = world.player

    // ---- 3D
    private val cam = PerspectiveCamera(70f, 1280f, 720f).apply { near = 0.05f; far = 30f }
    private val art = FpsArt(world.map)
    private val batch3d = ModelBatch(DefaultShaderProvider(DefaultShader.Config().apply { numPointLights = LIGHTS; numDirectionalLights = 1 }))
    private val env = Environment()
    /** The held gun gets its own steady light so it never blows out next to a lamp or the torch. */
    private val viewEnv = Environment(); private val viewSun = DirectionalLight()
    private val points = Array(LIGHTS) { PointLight().set(0f, 0f, 0f, 0f, -50f, 0f, 0f) }
    private val torch get() = points[0]
    private val scene = ArrayList<ModelInstance>(512)
    private val view = ArrayList<ModelInstance>(4)
    private val sounds = FpsSounds().also { it.load() }
    private val rnd = Random(11)

    // ---- HUD
    private val hudCam = OrthographicCamera(); private val hud = ExtendViewport(1280f, 720f, hudCam)
    private val shapes = ShapeRenderer(); private val batch = SpriteBatch(); private val font = BitmapFont(); private val layout = GlyphLayout()
    private val isTouch = Gdx.app.type == Application.ApplicationType.Android || System.getProperty("zombie.touch") == "1"
    private val ui = if (isTouch) 1.6f else 1f
    private val HW get() = hud.worldWidth
    private val HH get() = hud.worldHeight

    // ---- view state
    private var yaw = world.player.yaw; private var pitch = 0f
    private var time = 0f; private var bobT = 0f; private var kick = 0f; private var flashT = 0f; private var shake = 0f
    private var hitT = 0f; private var killMark = false; private var hurtT = 0f
    private var bannerText = ""; private var bannerT = 0f
    private class Toast(var text: String, var age: Float, val color: Color)
    private val toasts = ArrayList<Toast>()
    private class Popup(val text: String, var age: Float)
    private val popups = ArrayList<Popup>()
    private var growlT = 4f
    private var done = false; private var disposed = false; private var overT = 0f

    // ---- instances
    private class ZView(val inst: ModelInstance) {
        val legL: Node = inst.getNode("legL"); val legR: Node = inst.getNode("legR"); val armL: Node = inst.getNode("armL"); val armR: Node = inst.getNode("armR")
        val head: Node = inst.getNode("head"); val torso: Node = inst.getNode("torso")
        val shirtD = inst.getMaterial("shirt").get(ColorAttribute.Diffuse) as ColorAttribute
        val shirtE = inst.getMaterial("shirt").get(ColorAttribute.Emissive) as ColorAttribute
        val skinD = inst.getMaterial("skin").get(ColorAttribute.Diffuse) as ColorAttribute
        var id = -1
    }
    private val zPool = Array(FpsRules.MAX_ALIVE + 6) { ZView(ModelInstance(art.zombie)) }
    private val zBound = HashMap<Int, ZView>()
    private val boards = world.map.windows.map { w -> Array(Window.MAX_BOARDS) { i -> boardInstance(w, i) } }
    private val doors = world.map.doors.map { d ->
        val horizontal = world.map.walkable(d.tx - 1, d.ty) || world.map.at(d.tx - 1, d.ty) == Tile.FLOOR
        ModelInstance(art.door).also { it.transform.setToTranslation(world.map.centre(d.tx), 0f, world.map.centre(d.ty)).rotate(Vector3.Y, if (horizontal) 0f else 90f) }
    }
    private class PropView(val prop: Prop, val main: ModelInstance, val extra: ModelInstance?)
    private val props = world.map.props.map { buildProp(it) }
    private val boxProp = props.first { it.prop.kind == PropKind.BOX }
    private val boxGuns = Array(art.gunsBare.size) { ModelInstance(art.gunsBare[it]) }
    private val dropInst = Array(FpsRules.POWERUPS_PER_ROUND + 2) { ModelInstance(art.drop) }
    private class Particle(val inst: ModelInstance) { var x = 0f; var y = 0f; var z = 0f; var vx = 0f; var vy = 0f; var vz = 0f; var life = 0f }
    private val blood = Array(60) { Particle(ModelInstance(art.blood)) }
    private val sparks = Array(30) { Particle(ModelInstance(art.spark)) }
    private val decals = Array(40) { ModelInstance(art.decal) }
    private var decalN = 0
    private val gunView = Array(art.guns.size) { ModelInstance(art.guns[it]) }
    private val knifeView = ModelInstance(art.knife)
    private val flash = ModelInstance(art.spark)
    private val vigRed = Color(); private val vigClear = Color(0.55f, 0f, 0f, 0f); private val taken = BooleanArray(64)
    private val vm = Matrix4(); private val tmpM = Matrix4(); private val v3 = Vector3()

    // ---- input
    private enum class Role { NONE, MOVE, LOOK, FIRE, USE, RELOAD, KNIFE, SWAP }
    private val roles = arrayOfNulls<Role>(10)
    private val last = Array(10) { Vector2() }
    private val moveOrigin = Vector2(); private val moveVec = Vector2(); private var moveActive = false
    private var lookDX = 0f; private var lookDY = 0f
    private var touchFire = false; private var touchUse = false; private var touchReload = false; private var touchKnife = false; private var touchSwap = false
    private val firePos = Vector2(); private val usePos = Vector2(); private val reloadPos = Vector2(); private val knifePos = Vector2()
    private val stickHome = Vector2(220f, 200f)

    private val touchIn = object : InputAdapter() {
        private val t = Vector3()
        private fun toHud(sx: Int, sy: Int): Vector3 = hud.unproject(t.set(sx.toFloat(), sy.toFloat(), 0f))
        override fun touchDown(sx: Int, sy: Int, pointer: Int, button: Int): Boolean {
            if (pointer >= roles.size) return false
            if (world.over) { if (overT > 1.5f) restart(); return true }
            if (!isTouch) { if (!Gdx.input.isCursorCatched) Gdx.input.isCursorCatched = true; return true }
            val h = toHud(sx, sy)
            last[pointer].set(h.x, h.y)
            roles[pointer] = when {
                h.dst(firePos.x, firePos.y, 0f) < 95f -> Role.FIRE
                h.dst(usePos.x, usePos.y, 0f) < 62f -> Role.USE
                h.dst(reloadPos.x, reloadPos.y, 0f) < 55f -> Role.RELOAD
                h.dst(knifePos.x, knifePos.y, 0f) < 55f -> Role.KNIFE
                h.x > HW - 360f && h.y > HH - 130f -> Role.SWAP
                h.x < HW * 0.45f -> { moveOrigin.set(h.x, h.y); moveVec.setZero(); moveActive = true; Role.MOVE }
                else -> Role.LOOK
            }
            return true
        }
        override fun touchDragged(sx: Int, sy: Int, pointer: Int): Boolean {
            if (pointer >= roles.size || !isTouch) return false
            val h = toHud(sx, sy)
            when (roles[pointer]) {
                Role.MOVE -> moveVec.set(h.x - moveOrigin.x, h.y - moveOrigin.y).limit(STICK_R)
                Role.LOOK, Role.FIRE -> { lookDX += h.x - last[pointer].x; lookDY += h.y - last[pointer].y }
                else -> {}
            }
            last[pointer].set(h.x, h.y)
            return true
        }
        override fun touchUp(sx: Int, sy: Int, pointer: Int, button: Int): Boolean {
            if (pointer >= roles.size) return false
            if (roles[pointer] == Role.MOVE) { moveActive = false; moveVec.setZero() }
            roles[pointer] = null
            return true
        }
        override fun keyDown(keycode: Int): Boolean {
            if (keycode == Input.Keys.ESCAPE || keycode == Input.Keys.BACK) {
                if (!isTouch && Gdx.input.isCursorCatched && keycode == Input.Keys.ESCAPE) Gdx.input.isCursorCatched = false else backToMenu()
                return true
            }
            return false
        }
    }

    init {
        env.set(ColorAttribute(ColorAttribute.AmbientLight, 0.17f, 0.16f, 0.18f, 1f))
        env.set(ColorAttribute(ColorAttribute.Fog, FOG.r, FOG.g, FOG.b, 1f))
        env.add(DirectionalLight().set(0.16f, 0.18f, 0.26f, -0.35f, -1f, -0.25f))
        points.forEach { env.add(it) }
        viewEnv.set(ColorAttribute(ColorAttribute.AmbientLight, 0.42f, 0.4f, 0.38f, 1f)); viewEnv.add(viewSun)
        Gdx.input.inputProcessor = touchIn
        Gdx.input.setCatchKey(Input.Keys.BACK, true)
        font.data.setScale(ui)
    }

    private fun boardInstance(w: Window, i: Int): ModelInstance {
        val m = world.map
        val inx = (w.inX - w.tx).toFloat(); val iny = (w.inY - w.ty).toFloat()
        val x = m.centre(w.tx) + inx * (FpsMap.CELL / 2 - 0.12f); val z = m.centre(w.ty) + iny * (FpsMap.CELL / 2 - 0.12f)
        val tilt = (if (i % 2 == 0) 1f else -1f) * (6f + (i * 37 % 7))
        return ModelInstance(art.board).also {
            it.transform.setToTranslation(x + inx * 0.04f * (i % 2), 0.98f + i * 0.23f, z + iny * 0.04f * (i % 2))
                .rotate(Vector3.Y, FpsArt.yawDeg(inx, iny)).rotate(Vector3.X, tilt)
        }
    }

    private fun buildProp(pr: Prop): PropView {
        val m = world.map; val cx = m.centre(pr.tx); val cz = m.centre(pr.ty)
        val yawD = FpsArt.yawDeg(pr.fx.toFloat(), pr.fy.toFloat())
        return when (pr.kind) {
            PropKind.WALL_BUY -> {
                val fx = cx + pr.fx * (FpsMap.CELL / 2 + 0.01f); val fz = cz + pr.fy * (FpsMap.CELL / 2 + 0.01f)
                val chalk = ModelInstance(art.chalk).also { it.transform.setToTranslation(fx, 1.5f, fz).rotate(Vector3.Y, yawD) }
                val gun = ModelInstance(art.gunsBare[pr.gun!!.shape])
                FpsArt.wallGun(gun.transform, fx + pr.fx * 0.05f, 1.5f, fz + pr.fy * 0.05f, pr.fx.toFloat(), pr.fy.toFloat(), 1.25f)
                PropView(pr, chalk, gun)
            }
            PropKind.PERK -> {
                val inst = ModelInstance(art.perk).also { it.transform.setToTranslation(cx + pr.fx * 0.45f, 0f, cz + pr.fy * 0.45f).rotate(Vector3.Y, yawD) }
                val k = pr.perk!!
                (inst.getMaterial("body").get(ColorAttribute.Diffuse) as ColorAttribute).color.set(k.r * 0.45f, k.g * 0.45f, k.b * 0.45f, 1f)
                (inst.getMaterial("sign").get(ColorAttribute.Diffuse) as ColorAttribute).color.set(k.r, k.g, k.b, 1f)
                PropView(pr, inst, null)
            }
            PropKind.BOX -> PropView(pr, ModelInstance(art.box).also { it.transform.setToTranslation(cx, 0f, cz).rotate(Vector3.Y, yawD) }, ModelInstance(art.beam).also { it.transform.setToTranslation(cx, 0f, cz) })
            PropKind.POWER -> PropView(pr, ModelInstance(art.power).also { it.transform.setToTranslation(cx + pr.fx * 0.5f, 0f, cz + pr.fy * 0.5f).rotate(Vector3.Y, yawD) }, null)
            PropKind.FORGE -> PropView(pr, ModelInstance(art.forge).also { it.transform.setToTranslation(cx, 0f, cz).rotate(Vector3.Y, yawD) }, null)
        }
    }

    override fun resize(width: Int, height: Int) {
        cam.viewportWidth = width.toFloat(); cam.viewportHeight = height.toFloat(); cam.update()
        hud.update(width, height, true)
        firePos.set(HW - 190f, 200f); usePos.set(HW - 150f, 410f); reloadPos.set(HW - 370f, 115f); knifePos.set(HW - 380f, 270f)
    }

    override fun render(delta: Float) {
        if (done) return
        val dt = min(delta, 1 / 20f); time += dt
        val inp = readInput(dt)
        world.update(dt, inp)
        handleEvents()
        if (world.over) overT += dt
        updateView(dt)
        draw3d()
        drawHud(dt)
    }

    // ---- input ------------------------------------------------------------------------------------------------------
    private fun readInput(dt: Float): FpsInput {
        val k = Gdx.input
        var mx = 0f; var my = 0f
        var fire = false; var use = false; var reload = false; var knife = false; var swap = false
        if (!isTouch) {
            if (k.isKeyPressed(Input.Keys.W)) my += 1f; if (k.isKeyPressed(Input.Keys.S)) my -= 1f
            if (k.isKeyPressed(Input.Keys.D)) mx += 1f; if (k.isKeyPressed(Input.Keys.A)) mx -= 1f
            use = k.isKeyPressed(Input.Keys.E); reload = k.isKeyPressed(Input.Keys.R)
            knife = k.isKeyPressed(Input.Keys.V) || k.isKeyPressed(Input.Keys.F)
            swap = k.isKeyPressed(Input.Keys.Q) || k.isKeyPressed(Input.Keys.NUM_1) || k.isKeyPressed(Input.Keys.NUM_2)
            if (k.isCursorCatched) {
                yaw += k.deltaX * MOUSE_SENS; pitch -= k.deltaY * MOUSE_SENS
                fire = k.isButtonPressed(Input.Buttons.LEFT)
            }
        } else {
            for (r in roles) when (r) { Role.FIRE -> fire = true; Role.USE -> use = true; Role.RELOAD -> reload = true; Role.KNIFE -> knife = true; Role.SWAP -> swap = true; else -> {} }
            if (moveActive) { mx = moveVec.x / STICK_R; my = moveVec.y / STICK_R }
            yaw += lookDX * TOUCH_SENS; pitch += lookDY * TOUCH_SENS * 0.8f
            if (fire) assist(dt)
        }
        lookDX = 0f; lookDY = 0f
        pitch = pitch.coerceIn(-1.3f, 1.3f)
        return FpsInput(mx, my, yaw, pitch, fire, reload, use, knife, swap)
    }

    /** Touch aim assist: while firing, ease toward the zombie nearest the crosshair if it is within a few degrees and visible. */
    private fun assist(dt: Float) {
        var best: FpsZombie? = null; var bestOff = 0.07f
        for (z in world.zombies) {
            if (!z.alive || z.state == ZState.OUTSIDE) continue
            val dx = z.x - p.x; val dy = z.y - p.y; val d = hypot(dx, dy); if (d > 25f) continue
            val off = abs(angleDiff(yaw, atan2(dy, dx))); if (off < bestOff) { bestOff = off; best = z }
        }
        val z = best ?: return
        if (!world.map.clearPath(p.x, p.y, z.x, z.y, 0f) { a, b -> world.map.stopsBullets(a, b) }) return
        val d = hypot(z.x - p.x, z.y - p.y)
        val ty = atan2(z.y - p.y, z.x - p.x); val tp = atan2(1.3f * z.scale - FpsWorld.EYE, d)
        val step = 0.9f * dt
        yaw += angleDiff(yaw, ty).coerceIn(-step, step); pitch += (tp - pitch).coerceIn(-step, step)
    }

    // ---- events -----------------------------------------------------------------------------------------------------
    private fun play3d(name: String, x: Float, y: Float, vol: Float = 1f) {
        val dx = x - p.x; val dy = y - p.y; val d = hypot(dx, dy)
        val pan = if (d < 0.5f) 0f else ((-sin(yaw) * dx + cos(yaw) * dy) / d) * 0.8f
        sounds.play(name, vol / (1f + d * 0.12f), 0.92f + rnd.nextFloat() * 0.16f, pan)
    }

    private fun toast(t: String, c: Color = Color.WHITE) { toasts += Toast(t, 0f, c); while (toasts.size > 4) toasts.removeAt(0) }

    private fun handleEvents() {
        for (e in world.events) when (e.type) {
            FpsEvent.Type.SHOT -> { sounds.play(SHOT_SOUNDS[e.n.coerceIn(0, 6)], 0.8f, 0.95f + rnd.nextFloat() * 0.1f); flashT = 0.05f; kick = min(1f, kick + if (e.n == 5 || e.n == 2) 1f else 0.45f) }
            FpsEvent.Type.IMPACT -> burst(if (e.flag) blood else sparks, e.x, e.z, e.y, if (e.flag) 7 else 4)
            FpsEvent.Type.HIT -> { hitT = 0.12f; killMark = false; sounds.play(if (e.flag) "headshot" else "hit", 0.6f) }
            FpsEvent.Type.KILL -> {
                hitT = 0.2f; killMark = true; sounds.play(if (e.flag) "headshot" else "hit", 0.8f)
                if (e.flag) burst(blood, e.x, 1.65f, e.y, 14)
                decals[decalN % decals.size].transform.setToTranslation(e.x, 0.012f + (decalN % 7) * 0.001f, e.y).rotate(Vector3.Y, rnd.nextFloat() * 360f).scale(0.8f + rnd.nextFloat() * 0.6f, 1f, 0.8f + rnd.nextFloat() * 0.6f); decalN++
            }
            FpsEvent.Type.POINTS -> { popups += Popup("+${e.n}", 0f); while (popups.size > 6) popups.removeAt(0) }
            FpsEvent.Type.HURT -> { hurtT = 1f; shake = 0.25f; sounds.play("hurt", 0.9f) }
            FpsEvent.Type.ROUND_START -> { bannerText = "ROUND ${e.n}"; bannerT = 4f; sounds.play("round", 0.9f) }
            FpsEvent.Type.ROUND_END -> { bannerText = "ROUND ${e.n} SURVIVED"; bannerT = 3f; sounds.play("roundend", 0.8f) }
            FpsEvent.Type.BOUGHT -> { toast(e.text, Color(0.6f, 1f, 0.6f, 1f)); sounds.play("buy", 0.7f) }
            FpsEvent.Type.DENIED -> { toast("Not enough points", Color(1f, 0.45f, 0.4f, 1f)); sounds.play("deny", 0.6f) }
            FpsEvent.Type.POWER_ON -> { toast("THE POWER IS ON", Color(1f, 0.9f, 0.4f, 1f)); sounds.play("power", 1f); powerVisuals() }
            FpsEvent.Type.POWERUP -> { toast(e.text.uppercase(), Color(1f, 0.95f, 0.5f, 1f)); sounds.play("powerup", 1f) }
            FpsEvent.Type.POWERUP_DROP -> play3d("drop", e.x, e.y, 0.8f)
            FpsEvent.Type.BOARD_TORN -> play3d("board", e.x, e.y, 0.9f)
            FpsEvent.Type.BOARD_FIXED -> sounds.play("fix", 0.6f)
            FpsEvent.Type.DOWN -> { toast("SECOND WIND!", Color(0.5f, 0.75f, 1f, 1f)); sounds.play("hurt", 1f, 0.7f) }
            FpsEvent.Type.REVIVED -> sounds.play("powerup", 0.8f, 0.8f)
            FpsEvent.Type.GAME_OVER -> { sounds.play("roundend", 1f, 0.6f); if (!isTouch) Gdx.input.isCursorCatched = false }
            FpsEvent.Type.RELOAD -> sounds.play("reload", 0.6f)
            FpsEvent.Type.KNIFE -> { sounds.play("knife", 0.7f); if (e.flag) sounds.play("hit", 0.8f, 0.8f) }
            FpsEvent.Type.BOX_ROLL -> sounds.play("box", 0.7f)
            FpsEvent.Type.DOOR -> { play3d("door", e.x, e.y, 1f); toast("Door opened", Color(0.8f, 0.8f, 0.8f, 1f)) }
            FpsEvent.Type.GROWL -> play3d("growl${1 + rnd.nextInt(3)}", e.x, e.y, 0.7f)
            FpsEvent.Type.SWAP -> sounds.play("reload", 0.4f, 1.4f)
            FpsEvent.Type.EMPTY -> sounds.play("empty", 0.5f)
        }
        // the horde moans now and then
        growlT -= Gdx.graphics.deltaTime
        if (growlT <= 0f) {
            growlT = 2f + rnd.nextFloat() * 4f
            val alive = world.zombies.filter { it.alive }
            if (alive.isNotEmpty()) { val z = alive[rnd.nextInt(alive.size)]; play3d("growl${1 + rnd.nextInt(3)}", z.x, z.y, 0.55f) }
        }
    }

    private fun burst(pool: Array<Particle>, x: Float, h: Float, z: Float, n: Int) {
        var made = 0
        for (pt in pool) {
            if (pt.life > 0f) continue
            pt.x = x; pt.y = h; pt.z = z
            pt.vx = (rnd.nextFloat() - 0.5f) * 3f; pt.vy = rnd.nextFloat() * 2.5f; pt.vz = (rnd.nextFloat() - 0.5f) * 3f
            pt.life = 0.35f + rnd.nextFloat() * 0.35f
            if (++made >= n) break
        }
    }

    private fun powerVisuals() {
        for (pv in props) when (pv.prop.kind) {
            PropKind.PERK -> { val k = pv.prop.perk!!; (pv.main.getMaterial("sign").get(ColorAttribute.Emissive) as ColorAttribute).color.set(k.r, k.g, k.b, 1f); (pv.main.getMaterial("glass").get(ColorAttribute.Emissive) as ColorAttribute).color.set(k.r * 0.4f, k.g * 0.4f, k.b * 0.4f, 1f) }
            PropKind.POWER -> { pv.main.getNode("lever").rotation.set(Vector3.Z, -70f); pv.main.calculateTransforms(); (pv.main.getMaterial("lamp").get(ColorAttribute.Emissive) as ColorAttribute).color.set(0.1f, 1f, 0.2f, 1f) }
            else -> {}
        }
    }

    // ---- 3D ---------------------------------------------------------------------------------------------------------
    private fun updateView(dt: Float) {
        bobT += dt * 9f * p.moving
        if (kick > 0f) kick = max(0f, kick - dt * 6f)
        if (flashT > 0f) flashT -= dt
        if (shake > 0f) shake -= dt
        if (hitT > 0f) hitT -= dt
        if (hurtT > 0f) hurtT -= dt * 1.5f
        if (bannerT > 0f) bannerT -= dt
        toasts.forEach { it.age += dt }; toasts.removeAll { it.age > 3f }
        popups.forEach { it.age += dt }; popups.removeAll { it.age > 1f }

        val down = p.downed
        val eye = if (down) 0.55f else FpsWorld.EYE + sin(bobT) * 0.035f * p.moving
        val sx = if (shake > 0f) (rnd.nextFloat() - 0.5f) * shake * 0.2f else 0f
        val vp = pitch + kick * 0.02f
        cam.position.set(p.x + sx, eye, p.y + sx)
        cam.direction.set(cos(vp) * cos(yaw), sin(vp), cos(vp) * sin(yaw))
        cam.up.set(0f, 1f, 0f)
        if (down) cam.up.set(-sin(yaw) * 0.3f, 1f, cos(yaw) * 0.3f).nor()
        cam.update()

        // lights: a torch on the player plus the strongest few nearby
        torch.set(1f, 0.82f, 0.62f, p.x - cos(yaw) * 0.5f, 2.5f, p.y - sin(yaw) * 0.5f, 2.6f + (if (flashT > 0f) 6f else 0f))
        chooseLights()

        scene.clear()
        scene.addAll(art.level)
        for (pv in props) {
            if (!world.zoneOpen[pv.prop.zone] && pv.prop.kind != PropKind.WALL_BUY && far(pv.prop)) continue
            scene += pv.main; pv.extra?.let { scene += it }
            if (pv.prop.kind == PropKind.FORGE && world.power) {
                val pulse = 0.6f + 0.4f * sin(time * 4f)
                (pv.main.getMaterial("core").get(ColorAttribute.Emissive) as ColorAttribute).color.set(0.9f * pulse, 0.15f * pulse, 1f * pulse, 1f)
            }
        }
        // box gun
        if (world.boxState != BoxState.IDLE) {
            val g = boxGuns[FpsGuns.BOX[world.boxShow].shape]
            val pr = boxProp.prop; val rise = if (world.boxState == BoxState.ROLLING) (1f - world.boxT / FpsWorld.ROLL_TIME) * 0.6f else 0.6f + sin(time * 3f) * 0.05f
            g.transform.setToTranslation(world.map.centre(pr.tx), 1.0f + rise, world.map.centre(pr.ty)).rotate(Vector3.Y, time * 90f).scale(1.3f, 1.3f, 1.3f)
            scene += g
        }
        for ((wi, arr) in boards.withIndex()) { val b = world.map.windows[wi].boards; for (i in 0 until b) scene += arr[i] }
        for ((i, d) in world.map.doors.withIndex()) if (!d.open) scene += doors[i]
        updateZombies()
        for ((i, d) in world.drops.withIndex()) {
            if (i >= dropInst.size) break
            if (d.t < 5f && ((d.t * 5f).toInt() % 2 == 0)) continue
            val inst = dropInst[i]
            (inst.getMaterial("drop").get(ColorAttribute.Emissive) as ColorAttribute).color.set(d.kind.r, d.kind.g, d.kind.b, 1f)
            inst.transform.setToTranslation(d.x, 0.7f + sin(time * 3f + i) * 0.12f, d.y).rotate(Vector3.Y, time * 120f).rotate(Vector3.X, 35f)
            scene += inst
        }
        for (pool in arrayOf(blood, sparks)) for (pt in pool) {
            if (pt.life <= 0f) continue
            pt.life -= dt; pt.vy -= 9f * dt; pt.x += pt.vx * dt; pt.y += pt.vy * dt; pt.z += pt.vz * dt
            if (pt.y < 0.02f) { pt.y = 0.02f; pt.vx *= 0.5f; pt.vz *= 0.5f; pt.vy = 0f }
            pt.inst.transform.setToTranslation(pt.x, pt.y, pt.z); scene += pt.inst
        }
        for (i in 0 until min(decalN, decals.size)) scene += decals[i]

        // viewmodel
        view.clear()
        if (!down) {
            val g = p.gun
            val reloadK = if (p.reloadT > 0f) sin(PI.toFloat() * (1f - p.reloadT / max(0.01f, g.gun.reload * (if (Perk.QUICKHAND in p.perks) 0.5f else 1f)))).coerceIn(0f, 1f) else 0f
            val swapK = if (p.swapT > 0f) p.swapT / 0.45f else 0f
            val swayX = sin(bobT * 0.5f) * 0.012f * p.moving; val swayY = abs(cos(bobT * 0.5f)) * 0.012f * p.moving
            vm.set(cam.view).inv()
            if (p.knifeT > 0f) {
                val k = sin(PI.toFloat() * (1f - p.knifeT / 0.35f))
                knifeView.transform.set(vm).translate(0.12f, -0.16f, -0.3f - k * 0.25f).scale(0.75f, 0.75f, 0.75f).rotate(Vector3.Y, 25f - k * 30f).rotate(Vector3.X, -10f)
                view += knifeView
            } else {
                val inst = gunView[g.gun.shape]
                inst.transform.set(vm).translate(0.15f + swayX, -0.16f + swayY - reloadK * 0.14f - swapK * 0.25f, -0.34f + kick * 0.04f)
                    .rotate(Vector3.Y, -4f).rotate(Vector3.X, kick * 6f - reloadK * 20f).rotate(Vector3.Z, reloadK * 25f).scale(0.62f, 0.62f, 0.62f)
                val metal = inst.getMaterial("metal")
                (metal.get(ColorAttribute.Diffuse) as ColorAttribute).color.set(if (g.forged) 0.32f else 0.17f, if (g.forged) 0.12f else 0.17f, if (g.forged) 0.4f else 0.19f, 1f)
                (metal.get(ColorAttribute.Emissive) as ColorAttribute).color.set(if (g.forged) 0.12f + 0.06f * sin(time * 3f) else 0f, 0f, if (g.forged) 0.16f + 0.08f * sin(time * 3f) else 0f, 1f)
                view += inst
                if (flashT > 0f) {
                    flash.transform.set(inst.transform).translate(0f, 0.01f, -MUZZLE[g.gun.shape]).rotate(Vector3.Z, time * 900f).scale(4f, 4f, 1.5f)
                    view += flash
                }
            }
        }
    }

    private fun far(pr: Prop) = hypot(world.map.centre(pr.tx) - p.x, world.map.centre(pr.ty) - p.y) > 30f

    private val lightScore = FloatArray(64)
    private fun chooseLights() {
        val all = art.lights
        for (i in 1 until LIGHTS) points[i].intensity = 0f
        var used = 1
        // greedy: nearest first, by squared distance
        val n = min(all.size, lightScore.size)
        for (i in 0 until n) lightScore[i] = (all[i].x - p.x) * (all[i].x - p.x) + (all[i].z - p.y) * (all[i].z - p.y)
        java.util.Arrays.fill(taken, false)
        while (used < LIGHTS - 1) {
            var bi = -1; var bv = 26f * 26f
            for (i in 0 until n) if (!taken[i] && lightScore[i] < bv) { bv = lightScore[i]; bi = i }
            if (bi < 0) break
            taken[bi] = true
            val l = all[bi]
            points[used++].set(l.r, l.g, l.b, l.x, l.h, l.z, l.intensity * (0.92f + 0.08f * sin(time * 13f + bi)))
        }
        // the box's light, or the forge once powered, takes the last slot when close
        val bp = boxProp.prop
        val bx = world.map.centre(bp.tx); val bz = world.map.centre(bp.ty)
        if (hypot(bx - p.x, bz - p.y) < 20f) points[LIGHTS - 1].set(0.4f, 0.65f, 1f, bx, 2.2f, bz, 3f)
        else if (world.power) props.firstOrNull { it.prop.kind == PropKind.FORGE }?.let { f -> points[LIGHTS - 1].set(0.8f, 0.2f, 1f, world.map.centre(f.prop.tx), 2.6f, world.map.centre(f.prop.ty), 2.2f) }
    }

    private fun updateZombies() {
        // unbind views of zombies that are gone
        val it = zBound.entries.iterator()
        while (it.hasNext()) { val e = it.next(); if (world.zombies.none { z -> z.id == e.key }) { e.value.id = -1; it.remove() } }
        for (z in world.zombies) {
            var v = zBound[z.id]
            if (v == null) {
                v = zPool.firstOrNull { it.id == -1 } ?: continue
                v.id = z.id; zBound[z.id] = v
                val s = SHIRTS[z.look % SHIRTS.size]; v.shirtD.color.set(s)
                val sk = SKINS[(z.look shr 4) % SKINS.size]; v.skinD.color.set(sk)
            }
            pose(v, z)
            scene += v.inst
        }
    }

    private fun pose(v: ZView, z: FpsZombie) {
        val ph = z.walkPhase
        var legA = sin(ph) * 28f; var armL = 82f + sin(ph * 0.5f + 1f) * 8f; var armR = 78f + sin(ph * 0.5f) * 8f
        var fall = 0f; var yOff = 0f; var lean = 0f
        when (z.state) {
            ZState.BREAKING -> { val t = time * 7f + z.id; armL = 70f + 35f * sin(t); armR = 70f - 35f * sin(t); legA = 0f }
            ZState.CLIMBING -> { val k = (z.climbT / FpsWorld.CLIMB_TIME).coerceIn(0f, 1f); yOff = sin(PI.toFloat() * k) * 0.7f; lean = -25f * sin(PI.toFloat() * k); legA = 40f * sin(PI.toFloat() * k) }
            ZState.DEAD -> { fall = min(90f, z.deadT * 220f); yOff = if (z.deadT > 1.6f) -(z.deadT - 1.6f) * 0.5f else 0f; legA = 0f; armL = 150f; armR = 140f }
            else -> {}
        }
        if (z.attacking) { val k = 1f - z.attackT / FpsWorld.ATTACK_WINDUP; armL = 120f - 90f * k; armR = 110f - 80f * k }
        v.legL.rotation.set(Vector3.Z, legA); v.legR.rotation.set(Vector3.Z, -legA)
        v.armL.rotation.set(Vector3.Z, armL); v.armR.rotation.set(Vector3.Z, armR)
        v.torso.rotation.set(Vector3.Z, -6f + lean)
        if (z.headless && z.state == ZState.DEAD) v.head.scale.set(0.001f, 0.001f, 0.001f) else v.head.scale.set(1f, 1f, 1f)
        v.shirtE.color.set(if (z.hitT > 0f) 0.5f else 0f, 0f, 0f, 1f)
        v.inst.calculateTransforms()
        v.inst.transform.setToTranslation(z.x, yOff, z.y).rotate(Vector3.Y, -Math.toDegrees(z.facing.toDouble()).toFloat()).rotate(Vector3.Z, fall).scale(z.scale, z.scale, z.scale)
    }

    private fun draw3d() {
        Gdx.gl.glViewport(0, 0, Gdx.graphics.backBufferWidth, Gdx.graphics.backBufferHeight)
        Gdx.gl.glClearColor(FOG.r, FOG.g, FOG.b, 1f)
        Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT or GL20.GL_DEPTH_BUFFER_BIT)
        batch3d.begin(cam); batch3d.render(scene, env); batch3d.end()
        if (view.isNotEmpty()) {
            Gdx.gl.glClear(GL20.GL_DEPTH_BUFFER_BIT) // the gun never clips into walls
            viewSun.set(0.75f, 0.7f, 0.62f, cam.direction.x + 0.3f, cam.direction.y - 0.9f, cam.direction.z)
            batch3d.begin(cam); batch3d.render(view, viewEnv); batch3d.end()
        }
    }

    // ---- HUD --------------------------------------------------------------------------------------------------------
    private fun beginShapes(type: ShapeRenderer.ShapeType) {
        Gdx.gl.glEnable(GL20.GL_BLEND); Gdx.gl.glBlendFunc(GL20.GL_SRC_ALPHA, GL20.GL_ONE_MINUS_SRC_ALPHA)
        shapes.begin(type)
    }

    private val lh get() = 18f * ui

    private fun text(t: String, x: Float, y: Float, scale: Float, align: Int = 0) {
        font.data.setScale(scale * ui); layout.setText(font, t)
        val tx = when (align) { 0 -> x - layout.width / 2; 1 -> x; else -> x - layout.width }
        val r = font.color.r; val gg = font.color.g; val b = font.color.b; val al = font.color.a
        font.setColor(0f, 0f, 0f, al * 0.8f); font.draw(batch, t, tx + 2f, y - 2f) // shadow for contrast on any background
        font.setColor(r, gg, b, al); font.draw(batch, t, tx, y)
        font.data.setScale(ui)
    }

    private fun drawHud(dt: Float) {
        hud.apply()
        shapes.projectionMatrix = hudCam.combined; batch.projectionMatrix = hudCam.combined
        val maxHp = p.maxHp; val low = (1f - p.hp / maxHp).coerceIn(0f, 1f)

        beginShapes(ShapeRenderer.ShapeType.Filled)
        // damage vignette: red edges that grow as health drops and flash on every hit
        val a = (low * 0.55f + hurtT * 0.35f).coerceIn(0f, 0.8f)
        if (a > 0.01f) {
            val red = vigRed.set(0.55f, 0f, 0f, a); val clear = vigClear; val e = HW * 0.22f
            shapes.rect(0f, 0f, e, HH, red, clear, clear, red); shapes.rect(HW - e, 0f, e, HH, clear, red, red, clear)
            shapes.rect(0f, HH - e * 0.8f, HW, e * 0.8f, clear, clear, red, red); shapes.rect(0f, 0f, HW, e * 0.8f, red, red, clear, clear)
        }
        if (p.downed) { shapes.setColor(0.1f, 0.15f, 0.35f, 0.35f); shapes.rect(0f, 0f, HW, HH) }
        // round tally (top left), five strokes per group with a slash
        drawTally(40f, HH - 110f, world.round)
        // perks
        var px = 40f
        for (k in p.perks) { shapes.setColor(k.r * 0.7f, k.g * 0.7f, k.b * 0.7f, 0.95f); shapes.rect(px, HH - 205f - 20f * ui, 30f * ui, 30f * ui); px += 36f * ui }
        // touch controls
        if (isTouch && !world.over) {
            val c0 = if (moveActive) moveOrigin else stickHome
            shapes.setColor(1f, 1f, 1f, 0.1f); shapes.circle(c0.x, c0.y, STICK_R + 20f)
            shapes.setColor(1f, 1f, 1f, 0.28f); shapes.circle(c0.x + moveVec.x, c0.y + moveVec.y, 42f)
            shapes.setColor(0.9f, 0.15f, 0.1f, if (roles.contains(Role.FIRE)) 0.6f else 0.38f); shapes.circle(firePos.x, firePos.y, 85f)
            val pulse = world.prompt.isNotEmpty() && world.promptOk
            if (pulse) shapes.setColor(0.3f, 1f, 0.4f, 0.45f + 0.25f * sin(time * 7f)) else shapes.setColor(1f, 1f, 1f, 0.18f); shapes.circle(usePos.x, usePos.y, 52f)
            shapes.setColor(1f, 1f, 1f, 0.2f); shapes.circle(reloadPos.x, reloadPos.y, 46f); shapes.circle(knifePos.x, knifePos.y, 46f)
        }
        if (world.over) { shapes.setColor(0f, 0f, 0f, min(0.75f, overT)); shapes.rect(0f, 0f, HW, HH) }
        shapes.end()

        // crosshair and hit marker
        if (!world.over && !p.downed) {
            beginShapes(ShapeRenderer.ShapeType.Filled)
            val spread = 10f + p.moving * 10f + kick * 14f
            shapes.setColor(1f, 1f, 1f, 0.8f)
            val cx = HW / 2; val cy = HH / 2; val l = 9f; val t = 2.5f
            shapes.rect(cx - spread - l, cy - t / 2, l, t); shapes.rect(cx + spread, cy - t / 2, l, t)
            shapes.rect(cx - t / 2, cy + spread, t, l); shapes.rect(cx - t / 2, cy - spread - l, t, l)
            if (hitT > 0f) {
                shapes.color = if (killMark) Color(1f, 0.25f, 0.2f, 1f) else Color(1f, 1f, 1f, 1f)
                for (s in listOf(1f, -1f)) for (u in listOf(1f, -1f)) shapes.rectLine(cx + s * 7f, cy + u * 7f, cx + s * 16f, cy + u * 16f, 3f)
            }
            shapes.end()
        }

        batch.begin()
        // points and popups
        font.color = Color.WHITE
        text("${p.points}", 40f, HH - 130f, 2.1f, 1)
        layout.setText(font, "${p.points}")
        for ((i, pp) in popups.withIndex()) { font.setColor(1f, 0.9f, 0.4f, 1f - pp.age); text(pp.text, 40f + 140f * ui, HH - 130f + pp.age * 40f + i * 2f, 1.2f, 1) }
        font.color = Color.WHITE
        var lx = 40f
        for (k in p.perks) { text(k.letter, lx + 15f * ui, HH - 200f, 1.1f); lx += 36f * ui }
        if (world.round > 10) { font.setColor(0.7f, 0.05f, 0.05f, 1f); text("${world.round}", 40f, HH - 36f, 4f, 1) }
        // ammo (top right; tap to swap on touch)
        val g = p.gun
        font.color = if (g.mag == 0) Color(1f, 0.3f, 0.3f, 1f) else Color.WHITE
        text("${g.mag} / ${g.reserve}", HW - 40f, HH - 40f, 2.2f, 2)
        font.color = if (g.forged) Color(0.85f, 0.5f, 1f, 1f) else Color(0.85f, 0.85f, 0.85f, 1f)
        text(g.name, HW - 40f, HH - 40f - 42f * ui, 1.1f, 2)
        if (p.guns.size > 1) { font.setColor(0.7f, 0.7f, 0.7f, 0.9f); text((if (isTouch) "tap: " else "Q: ") + p.guns[(p.cur + 1) % p.guns.size].name, HW - 40f, HH - 40f - 66f * ui, 0.9f, 2) }
        if (g.mag == 0 && g.reserve == 0) { font.setColor(1f, 0.4f, 0.3f, 1f); text("NO AMMO", HW / 2, HH / 2 - 60f, 1.3f) }
        else if (p.reloadT > 0f) { font.setColor(1f, 1f, 1f, 0.8f); text("RELOADING", HW / 2, HH / 2 - 60f, 1.1f) }
        else if (g.mag <= g.magSize / 4 && g.reserve > 0) { font.setColor(1f, 0.85f, 0.3f, 1f); text(if (isTouch) "RELOAD" else "RELOAD [R]", HW / 2, HH / 2 - 60f, 1.1f) }
        // active power-ups
        var ax = HW / 2 - 120f
        if (world.instaT > 0f) { font.color = Color.WHITE; text("INSTA-KILL ${world.instaT.toInt()}", ax, HH - 40f, 1.1f, 1); ax += 240f }
        if (world.doubleT > 0f) { font.setColor(1f, 0.85f, 0.1f, 1f); text("DOUBLE POINTS ${world.doubleT.toInt()}", ax, HH - 40f, 1.1f, 1) }
        // prompt and toasts
        if (world.prompt.isNotEmpty()) {
            font.color = if (world.promptOk) Color.WHITE else Color(0.7f, 0.7f, 0.7f, 1f)
            val t = if (isTouch) world.prompt else world.prompt.replace("USE", "E").replace("Hold E", "Hold E")
            text(t, HW / 2, if (isTouch) HH * 0.36f else HH * 0.3f, 1.3f)
        }
        for ((i, t) in toasts.withIndex()) { font.setColor(t.color.r, t.color.g, t.color.b, (1f - t.age / 3f).coerceIn(0f, 1f) * 1.4f); text(t.text, HW / 2, HH * 0.72f - i * 30f * ui, 1.4f) }
        if (bannerT > 0f) {
            val k = (if (bannerT > 3f) (4f - bannerT) else bannerT / 3f).coerceIn(0f, 1f)
            font.setColor(0.75f, 0.05f, 0.05f, k); text(bannerText, HW / 2, HH * 0.6f, 4f)
        }
        if (world.roundState == RoundState.WAITING) { font.setColor(0.85f, 0.85f, 0.85f, 1f); text("They are coming...", HW / 2, HH * 0.68f, 1.6f) }
        if (p.downed) { font.setColor(0.6f, 0.8f, 1f, 1f); text("SECOND WIND", HW / 2, HH * 0.62f, 2.5f); font.color = Color.WHITE; text("Back on your feet in ${p.downT.toInt() + 1}...", HW / 2, HH * 0.54f, 1.2f) }
        if (isTouch && !world.over) {
            font.setColor(1f, 1f, 1f, 0.85f)
            text("FIRE", firePos.x, firePos.y + 8f * ui, 1.1f); text("USE", usePos.x, usePos.y + 8f * ui, 1f)
            text("R", reloadPos.x, reloadPos.y + 8f * ui, 1.1f); text("KNIFE", knifePos.x, knifePos.y + 8f * ui, 0.8f)
        }
        if (!isTouch && !Gdx.input.isCursorCatched && !world.over) { font.setColor(1f, 1f, 1f, 0.8f); text("Click to aim with the mouse   (WASD move, E use, R reload, V knife, Q swap, Esc menu)", HW / 2, 40f, 1f) }
        if (world.over) {
            font.setColor(0.8f, 0.05f, 0.05f, 1f); text("GAME OVER", HW / 2, HH * 0.72f, 4f)
            font.color = Color.WHITE
            text("You survived ${world.round} round${if (world.round == 1) "" else "s"}", HW / 2, HH * 0.56f, 1.8f)
            text("Kills ${p.kills}    Headshots ${p.headshots}    Points earned ${p.pointsEarned}", HW / 2, HH * 0.47f, 1.2f)
            if (overT > 1.5f) text(if (isTouch) "Tap to play again  -  Back for the menu" else "Click to play again  -  Esc for the menu", HW / 2, HH * 0.34f, 1.1f)
        }
        batch.end()
    }

    private fun drawTally(x: Float, y: Float, round: Int) {
        if (round <= 0 || round > 10) return
        shapes.setColor(0.7f, 0.04f, 0.04f, 1f)
        val h = 70f; val gap = 13f
        var cx = x
        for (i in 0 until round) {
            val inGroup = i % 5
            if (inGroup == 4) { shapes.rectLine(cx - 4 * gap - 6f, y + 8f, cx + 2f, y + h - 8f, 5f); cx += gap * 1.8f; continue }
            shapes.rectLine(cx, y, cx + (if (i % 2 == 0) 3f else -2f), y + h, 5f)
            cx += gap
        }
    }

    // ---- lifecycle --------------------------------------------------------------------------------------------------
    private fun restart() {
        if (done) return
        done = true
        (Gdx.app.applicationListener as? VictorOpsGame)?.setScreen(FpsScreen(character)); dispose()
    }

    private fun backToMenu() {
        if (done) return
        done = true
        if (!isTouch) Gdx.input.isCursorCatched = false
        (Gdx.app.applicationListener as? VictorOpsGame)?.setScreen(ModeSelectScreen(character)); dispose()
    }

    override fun hide() { if (!isTouch) Gdx.input.isCursorCatched = false }

    override fun dispose() {
        if (disposed) return
        disposed = true
        if (Gdx.input.inputProcessor === touchIn) Gdx.input.inputProcessor = null
        batch3d.dispose(); art.dispose(); sounds.dispose(); shapes.dispose(); batch.dispose(); font.dispose()
    }

    private companion object {
        const val LIGHTS = 6
        const val STICK_R = 110f
        const val TOUCH_SENS = 0.0065f
        const val MOUSE_SENS = 0.0024f
        val FOG = Color(0.015f, 0.014f, 0.02f, 1f)
        val SHOT_SOUNDS = arrayOf("pistol", "rifle", "shotgun", "smg", "lmg", "sniper", "ray")
        val MUZZLE = floatArrayOf(0.16f, 0.52f, 0.55f, 0.32f, 0.6f, 0.7f, 0.46f)
        val SHIRTS = listOf(Color(0.25f, 0.23f, 0.18f, 1f), Color(0.2f, 0.25f, 0.2f, 1f), Color(0.22f, 0.2f, 0.25f, 1f), Color(0.32f, 0.19f, 0.15f, 1f), Color(0.17f, 0.2f, 0.25f, 1f), Color(0.3f, 0.29f, 0.26f, 1f))
        val SKINS = listOf(Color(0.43f, 0.5f, 0.38f, 1f), Color(0.5f, 0.46f, 0.41f, 1f), Color(0.38f, 0.43f, 0.37f, 1f), Color(0.47f, 0.42f, 0.36f, 1f))
    }
}
