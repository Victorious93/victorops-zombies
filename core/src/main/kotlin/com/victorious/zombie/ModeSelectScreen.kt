package com.victorious.zombie

import com.badlogic.gdx.Gdx
import com.badlogic.gdx.Input
import com.badlogic.gdx.ScreenAdapter
import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.GL20
import com.badlogic.gdx.graphics.OrthographicCamera
import com.badlogic.gdx.graphics.g2d.BitmapFont
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.badlogic.gdx.graphics.glutils.ShapeRenderer
import com.badlogic.gdx.math.Vector3
import com.badlogic.gdx.utils.viewport.FitViewport
import com.victorious.zombie.logic.Character
import com.victorious.zombie.net.ClientSession
import com.victorious.zombie.net.HostSession
import com.victorious.zombie.net.TcpHost
import com.victorious.zombie.net.TcpLink
import com.victorious.zombie.sim.Layout

/** Solo (offline) / host on Wi-Fi / join on Wi-Fi. Solo is first and needs no network at all. */
class ModeSelectScreen(private val character: Character) : ScreenAdapter() {
    private val W = Layout.W; private val H = Layout.H
    private val cam = OrthographicCamera(); private val view = FitViewport(W, H, cam)
    private val shapes = ShapeRenderer(); private val batch = SpriteBatch(); private val font = BitmapFont()
    private val tmp = Vector3()
    @Volatile private var status = ""
    private var done = false // GL resources are disposed once we switch screens; never draw after that
    private var royale = false // false = Zombie Survival, true = Blackout Royale
    private val labels get() = if (royale)
        listOf("1  SOLO  (you + bots, offline)", "2  HOST  (Wi-Fi, up to 4 players + bots)", "3  JOIN  (Wi-Fi, enter host address)")
    else listOf("1  SOLO  (offline)", "2  HOST  (Wi-Fi, up to 4 players)", "3  JOIN  (Wi-Fi, enter host address)")
    private val gameBtn get() = if (royale) floatArrayOf(340f, 560f, 380f, 70f) else floatArrayOf(340f, 560f, 600f, 70f)
    private val squadBtn = floatArrayOf(740f, 560f, 200f, 70f) // Royale only
    init { BrPrefs.load() }
    private fun btn(i: Int) = floatArrayOf(340f, 440f - i * 120f, 600f, 90f) // x, y, w, h

    override fun resize(width: Int, height: Int) { view.update(width, height, true) }

    override fun render(delta: Float) {
        if (done) return
        if (Gdx.input.isKeyJustPressed(Input.Keys.NUM_1)) solo()
        if (Gdx.input.isKeyJustPressed(Input.Keys.NUM_2)) hostGame()
        if (Gdx.input.isKeyJustPressed(Input.Keys.NUM_3)) joinGame()
        if (Gdx.input.isKeyJustPressed(Input.Keys.G) || Gdx.input.isKeyJustPressed(Input.Keys.TAB)) royale = !royale
        if (royale && Gdx.input.isKeyJustPressed(Input.Keys.T)) BrPrefs.squadSize = BrPrefs.next(BrPrefs.squadSize)
        if (Gdx.input.isKeyJustPressed(Input.Keys.ESCAPE) || Gdx.input.isKeyJustPressed(Input.Keys.BACKSPACE)) back()
        if (Gdx.input.justTouched()) {
            view.unproject(tmp.set(Gdx.input.x.toFloat(), Gdx.input.y.toFloat(), 0f))
            if (royale && tmp.x in squadBtn[0]..squadBtn[0] + squadBtn[2] && tmp.y in squadBtn[1]..squadBtn[1] + squadBtn[3]) BrPrefs.squadSize = BrPrefs.next(BrPrefs.squadSize)
            else if (tmp.x in gameBtn[0]..gameBtn[0] + gameBtn[2] && tmp.y in gameBtn[1]..gameBtn[1] + gameBtn[3]) royale = !royale
            for (i in labels.indices) { val b = btn(i); if (tmp.x in b[0]..b[0] + b[2] && tmp.y in b[1]..b[1] + b[3]) when (i) { 0 -> solo(); 1 -> hostGame(); else -> joinGame() } }
        }
        if (done) return
        Gdx.gl.glClearColor(0.03f, 0.02f, 0.06f, 1f); Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT)
        view.apply(); shapes.projectionMatrix = cam.combined; batch.projectionMatrix = cam.combined
        shapes.begin(ShapeRenderer.ShapeType.Filled)
        labels.indices.forEach { i -> val b = btn(i); shapes.color = Color(0.14f, 0.12f, 0.22f, 1f); shapes.rect(b[0], b[1], b[2], b[3]) }
        shapes.color = if (royale) Color(0.45f, 0.1f, 0.2f, 1f) else Color(0.12f, 0.3f, 0.16f, 1f); shapes.rect(gameBtn[0], gameBtn[1], gameBtn[2], gameBtn[3])
        if (royale) { shapes.color = if (BrPrefs.squadSize > 1) Color(0.1f, 0.38f, 0.3f, 1f) else Color(0.2f, 0.2f, 0.26f, 1f); shapes.rect(squadBtn[0], squadBtn[1], squadBtn[2], squadBtn[3]) }
        shapes.end()
        batch.begin(); font.color = Color.WHITE
        font.data.setScale(2.2f); font.draw(batch, "${character.name} - how do you want to play?", 220f, H - 40f)
        font.data.setScale(1.5f); font.draw(batch, if (royale) "BLACKOUT ROYALE  (tap to switch)" else "GAME:  ZOMBIE SURVIVAL  (tap / G to switch)", gameBtn[0] + 24, gameBtn[1] + 45)
        if (royale) { font.data.setScale(1.3f); font.draw(batch, if (BrPrefs.squadSize > 1) "SQUADS OF ${BrPrefs.squadSize}" else "NO SQUADS", squadBtn[0] + 18, squadBtn[1] + 44); font.data.setScale(1.5f) }
        labels.forEachIndexed { i, t -> val b = btn(i); font.draw(batch, t, b[0] + 24, b[1] + 58) }
        font.data.setScale(1f)
        if (royale) font.draw(batch, "Squads: tap the green button (or press T) to cycle no squads / 2 / 3 / 4. Downed squad mates can be revived by holding USE next to them.", 120f, 140f)
        font.draw(batch, "Solo needs no internet or Wi-Fi. Hosting and joining need both devices on the same network (no internet required).", 120f, 110f)
        if (status.isNotEmpty()) { font.color = Color.YELLOW; font.draw(batch, status, 120f, 80f) }
        font.color = Color.LIGHT_GRAY; font.draw(batch, "Esc / Backspace: change character", 120f, 50f)
        batch.end()
    }

    private fun go(mode: Mode) { if (done) return; done = true; (Gdx.app.applicationListener as? VictorOpsGame)?.setScreen(GameScreen(character, mode)); dispose() }
    private fun back() { if (done) return; done = true; (Gdx.app.applicationListener as? VictorOpsGame)?.setScreen(CharacterSelectScreen()); dispose() }
    private fun solo() = if (royale) goRoyale(Mode.Solo) else go(Mode.Solo)

    private fun goRoyale(mode: Mode) { if (done) return; done = true; (Gdx.app.applicationListener as? VictorOpsGame)?.setScreen(BrScreen(character, mode)); dispose() }

    /** Hands the new client session to the connecting screen, which opens whichever game the host runs. */
    private fun connect(session: ClientSession) {
        if (done) return
        done = true
        (Gdx.app.applicationListener as? VictorOpsGame)?.setScreen(ConnectingScreen(character, session)); dispose()
    }

    private fun hostGame() {
        try {
            val session = if (royale) HostSession.createRoyale(character, autoStartS = 120f, squadSize = BrPrefs.squadSize) else HostSession.create(character)
            val server = TcpHost(TcpHost.DEFAULT_PORT) { session.attach(it) }
            val addr = TcpHost.localAddress()
            Gdx.app.log("zombies", "Hosting on ${addr ?: "this device"}:${server.port}")
            val mode = Mode.Host(session) { server.close() }
            if (royale) goRoyale(mode) else go(mode)
        } catch (e: Exception) { status = "Could not host: ${e.message}" }
    }

    private fun joinGame() {
        Gdx.input.getTextInput(object : Input.TextInputListener {
            override fun input(text: String) {
                val host = text.trim().substringBefore(':'); val port = text.trim().substringAfter(':', "").toIntOrNull() ?: TcpHost.DEFAULT_PORT
                if (host.isEmpty()) return
                status = "Connecting to $host..."
                Thread {
                    try {
                        val link = TcpLink.connect(host, port)
                        Gdx.app.postRunnable { if (done) link.close() else connect(ClientSession(link, character.id)) }
                    } catch (e: Exception) { status = "Could not connect: ${e.message}" }
                }.start()
            }
            override fun canceled() {}
        }, "Host address", "", "e.g. 192.168.1.20")
    }

    override fun dispose() { shapes.dispose(); batch.dispose(); font.dispose() }
}
