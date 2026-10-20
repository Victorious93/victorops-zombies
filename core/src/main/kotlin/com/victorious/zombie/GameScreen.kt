package com.victorious.zombie

import com.badlogic.gdx.Application
import com.badlogic.gdx.Gdx
import com.badlogic.gdx.Input
import com.badlogic.gdx.ScreenAdapter
import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.GL20
import com.badlogic.gdx.graphics.OrthographicCamera
import com.badlogic.gdx.graphics.g2d.BitmapFont
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.badlogic.gdx.graphics.glutils.ShapeRenderer
import com.badlogic.gdx.math.MathUtils
import com.badlogic.gdx.math.Vector2
import com.badlogic.gdx.math.Vector3
import com.badlogic.gdx.utils.viewport.FitViewport
import com.victorious.zombie.logic.*
import kotlin.random.Random

/** Playable v0 slice. All visuals are procedural placeholder shapes. */
class GameScreen : ScreenAdapter() {
    private val W = 1280f; private val H = 720f
    private val arena = floatArrayOf(80f, 60f, W - 80f, H - 60f) // minX,minY,maxX,maxY
    private val cam = OrthographicCamera(); private val view = FitViewport(W, H, cam)
    private val shapes = ShapeRenderer(); private val batch = SpriteBatch(); private val font = BitmapFont()
    private val rng = Random(System.nanoTime())
    private val cyan = Color(0.1f, 0.95f, 1f, 1f); private val magenta = Color(1f, 0.15f, 0.85f, 1f)

    // State
    private val player = Vector2(W / 2, H / 2); private var maxHealth = 100f; private var health = 100f
    private val economy = Economy(); private var weapon = Weapons.STARTER; private var fireCd = 0f
    private val box = MysteryBox(); private val perk = PerkMachine(); private val forge = UpgradeMachine()
    private var round = 1; private var toSpawn = Rounds.zombieCount(1); private var spawnCd = 1f; private var intermission = 0f
    private var gameOver = false; private var message = "Round 1"; private var messageT = 2f; private var useCd = 0f

    private class Zombie(val pos: Vector2, var hp: Int, val window: Int, var inside: Boolean = false)
    private class Bullet(val pos: Vector2, val vel: Vector2, val dmg: Int, var life: Float = 1.2f)
    private val zombies = ArrayList<Zombie>(); private val bullets = ArrayList<Bullet>()

    // Windows: (inside position, outside spawn point)
    private val windows = listOf(
        Vector2(W / 2, arena[3]) to Vector2(W / 2, H + 30),
        Vector2(W / 2, arena[1]) to Vector2(W / 2, -30f),
        Vector2(arena[0], H / 2) to Vector2(-30f, H / 2),
        Vector2(arena[2], H / 2) to Vector2(W + 30, H / 2),
    )
    private val barricades = List(windows.size) { Barricade() }
    private val boxPos = Vector2(200f, 150f); private val perkPos = Vector2(W - 200f, 150f); private val forgePos = Vector2(W - 200f, H - 150f)

    // Touch controls
    private val isTouch = Gdx.app.type == Application.ApplicationType.Android
    private val stickCenter = Vector2(150f, 150f); private val stick = Vector2(); private var stickPointer = -1
    private val useBtn = Vector2(W - 130f, 130f); private var useTouched = false
    private val tmp = Vector3()

    override fun resize(width: Int, height: Int) { view.update(width, height, true) }

    override fun render(delta: Float) {
        val dt = minOf(delta, 1 / 30f)
        if (!gameOver) update(dt) else if (Gdx.input.justTouched() || Gdx.input.isKeyJustPressed(Input.Keys.ENTER)) restart()
        draw()
    }

    private fun restart() { (Gdx.app.applicationListener as? VictorOpsGame)?.setScreen(GameScreen()); dispose() }

    private fun readInput(): Vector2 {
        val dir = Vector2()
        if (Gdx.input.isKeyPressed(Input.Keys.W)) dir.y += 1
        if (Gdx.input.isKeyPressed(Input.Keys.S)) dir.y -= 1
        if (Gdx.input.isKeyPressed(Input.Keys.A)) dir.x -= 1
        if (Gdx.input.isKeyPressed(Input.Keys.D)) dir.x += 1
        useTouched = false
        stick.setZero(); var stickActive = false
        for (p in 0 until 5) {
            if (!Gdx.input.isTouched(p)) continue
            view.unproject(tmp.set(Gdx.input.getX(p).toFloat(), Gdx.input.getY(p).toFloat(), 0f))
            if (tmp.x < W / 2) {
                stick.set(tmp.x - stickCenter.x, tmp.y - stickCenter.y).limit(90f); stickActive = true
            } else if (Vector2.dst(tmp.x, tmp.y, useBtn.x, useBtn.y) < 90f) useTouched = true
        }
        stickPointer = if (stickActive) 0 else -1
        if (stickActive) dir.set(stick.x / 90f, stick.y / 90f)
        return if (dir.len() > 1f) dir.nor() else dir
    }

    private fun update(dt: Float) {
        messageT -= dt; useCd -= dt
        val dir = readInput()
        player.mulAdd(dir, 220f * dt)
        player.x = MathUtils.clamp(player.x, arena[0] + 15, arena[2] - 15)
        player.y = MathUtils.clamp(player.y, arena[1] + 15, arena[3] - 15)

        // Auto-aim at nearest inside (or visible) zombie and auto-fire
        fireCd -= dt
        val target = zombies.minByOrNull { it.pos.dst2(player) }
        if (target != null && fireCd <= 0f && target.pos.dst(player) < 520f) {
            val aim = Vector2(target.pos).sub(player).nor()
            repeat(weapon.pellets) {
                val spread = if (weapon.pellets > 1) MathUtils.random(-0.25f, 0.25f) else 0f
                bullets += Bullet(Vector2(player), Vector2(aim).rotateRad(spread).scl(weapon.bulletSpeed), weapon.damage)
            }
            fireCd = weapon.fireInterval
        }

        // Bullets
        val bit = bullets.iterator()
        while (bit.hasNext()) {
            val b = bit.next(); b.pos.mulAdd(b.vel, dt); b.life -= dt
            val hit = zombies.firstOrNull { it.pos.dst2(b.pos) < 18f * 18f }
            if (hit != null) {
                hit.hp -= b.dmg; economy.onHit()
                if (hit.hp <= 0) { zombies.remove(hit); economy.onKill() }
                bit.remove()
            } else if (b.life <= 0) bit.remove()
        }

        // Zombies
        val speed = Rounds.zombieSpeed(round)
        for (z in zombies) {
            val (inPos, _) = windows[z.window]; val bar = barricades[z.window]
            if (!z.inside) {
                if (z.pos.dst(inPos) > 22f) z.pos.mulAdd(Vector2(inPos).sub(z.pos).nor(), speed * dt)
                else if (!bar.isBroken) { if (MathUtils.randomBoolean(dt * 1.5f)) bar.damage(bar.plankHp) }
                else z.inside = true
            } else {
                z.pos.mulAdd(Vector2(player).sub(z.pos).nor(), speed * dt)
                if (z.pos.dst(player) < 26f) health -= 30f * dt
            }
        }
        if (health <= 0f) { gameOver = true; message = "OVERRUN on round $round"; messageT = 999f }

        // Spawning / rounds
        if (intermission > 0f) {
            intermission -= dt
            if (intermission <= 0f) { round++; toSpawn = Rounds.zombieCount(round); message = "Round $round"; messageT = 2f }
        } else if (toSpawn > 0) {
            spawnCd -= dt
            if (spawnCd <= 0f && zombies.size < Rounds.MAX_ALIVE) {
                val w = rng.nextInt(windows.size)
                zombies += Zombie(Vector2(windows[w].second).add(MathUtils.random(-20f, 20f), MathUtils.random(-20f, 20f)), Rounds.zombieHealth(round), w)
                toSpawn--; spawnCd = Rounds.spawnInterval(round)
            }
        } else if (zombies.isEmpty()) { intermission = 6f; message = "Round $round survived"; messageT = 3f; health = maxHealth }

        // Interactions (E on desktop, USE button on touch)
        if ((Gdx.input.isKeyPressed(Input.Keys.E) || useTouched) && useCd <= 0f) { interact(); useCd = 0.35f }
    }

    private fun near(p: Vector2) = player.dst(p) < 70f

    private fun prompt(): String? {
        if (near(boxPos)) return "Mystery Crate: ${box.cost}"
        if (near(perkPos)) return if (perk.owned) "${perk.name}: owned" else "${perk.name}: ${perk.cost}"
        if (near(forgePos)) return if (weapon.upgraded) "${forge.name}: maxed" else "${forge.name}: ${forge.cost}"
        val i = windows.indexOfFirst { near(it.first) }
        if (i >= 0 && barricades[i].hp < barricades[i].maxHp) return "Repair barricade (+${Economy.REPAIR})"
        return null
    }

    private fun interact() {
        fun say(s: String) { message = s; messageT = 2f }
        when {
            near(boxPos) -> box.buy(economy, rng, weapon.id)?.let { weapon = it; say("Got ${it.name}!") } ?: say("Not enough points")
            near(perkPos) -> if (perk.buy(economy)) { maxHealth = 200f; health = 200f; say("${perk.name} active") } else say("Can't buy perk")
            near(forgePos) -> forge.upgrade(weapon, economy)?.let { weapon = it; say("Upgraded: ${it.name}") } ?: say("Can't upgrade")
            else -> {
                val i = windows.indexOfFirst { near(it.first) }
                if (i >= 0 && barricades[i].repairPlank()) economy.onRepair()
            }
        }
    }

    private fun draw() {
        Gdx.gl.glClearColor(0.03f, 0.02f, 0.06f, 1f); Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT)
        view.apply(); shapes.projectionMatrix = cam.combined; batch.projectionMatrix = cam.combined
        shapes.begin(ShapeRenderer.ShapeType.Filled)
        shapes.color = Color(0.08f, 0.07f, 0.12f, 1f); shapes.rect(arena[0], arena[1], arena[2] - arena[0], arena[3] - arena[1])
        // Barricades
        windows.forEachIndexed { i, (p, _) ->
            val b = barricades[i]
            shapes.color = Color.DARK_GRAY; shapes.rect(p.x - 40, p.y - 10, 80f, 20f)
            shapes.color = Color(0.6f, 0.4f, 0.2f, 1f)
            for (k in 0 until b.planks) shapes.rect(p.x - 40 + k * 13.5f, p.y - 10, 11f, 20f)
        }
        // Machines
        shapes.color = Color.GOLD; shapes.rect(boxPos.x - 30, boxPos.y - 18, 60f, 36f)
        shapes.color = Color.LIME; shapes.rect(perkPos.x - 18, perkPos.y - 30, 36f, 60f)
        shapes.color = magenta; shapes.rect(forgePos.x - 30, forgePos.y - 30, 60f, 60f)
        // Zombies, bullets, player
        shapes.color = Color(0.35f, 0.75f, 0.3f, 1f); zombies.forEach { shapes.circle(it.pos.x, it.pos.y, 16f) }
        shapes.color = Color.YELLOW; bullets.forEach { shapes.circle(it.pos.x, it.pos.y, 3f) }
        shapes.color = cyan; shapes.circle(player.x, player.y, 15f)
        // HUD bars
        shapes.color = Color.RED; shapes.rect(20f, H - 30f, 200f * (health / maxHealth).coerceAtLeast(0f), 12f)
        if (isTouch) {
            shapes.color = Color(1f, 1f, 1f, 0.15f); shapes.circle(stickCenter.x, stickCenter.y, 90f)
            shapes.color = Color(0.1f, 0.95f, 1f, 0.5f); shapes.circle(stickCenter.x + stick.x, stickCenter.y + stick.y, 35f)
            shapes.color = Color(1f, 0.15f, 0.85f, 0.4f); shapes.circle(useBtn.x, useBtn.y, 60f)
        }
        shapes.end()

        batch.begin()
        font.color = Color.WHITE
        font.draw(batch, "ROUND $round   POINTS ${economy.points}   ${weapon.name}" + if (perk.owned) "   [${perk.name}]" else "", 240f, H - 18f)
        font.draw(batch, "CRATE", boxPos.x - 20, boxPos.y + 35); font.draw(batch, "PERK", perkPos.x - 16, perkPos.y + 48); font.draw(batch, "FORGE", forgePos.x - 20, forgePos.y + 48)
        prompt()?.let { font.draw(batch, it + if (isTouch) "  (tap USE)" else "  (press E)", W / 2 - 120, 110f) }
        if (messageT > 0f) { font.data.setScale(2f); font.draw(batch, message, W / 2 - 140, H / 2 + 120); font.data.setScale(1f) }
        if (gameOver) font.draw(batch, "Tap / Enter to restart", W / 2 - 80, H / 2 + 70)
        if (isTouch) font.draw(batch, "USE", useBtn.x - 14, useBtn.y + 6)
        batch.end()
    }

    override fun dispose() { shapes.dispose(); batch.dispose(); font.dispose() }
}
