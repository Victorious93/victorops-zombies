package com.victorious.zombie

import com.badlogic.gdx.Gdx
import com.badlogic.gdx.Input
import com.badlogic.gdx.ScreenAdapter
import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.GL20
import com.badlogic.gdx.graphics.OrthographicCamera
import com.badlogic.gdx.graphics.g2d.BitmapFont
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.badlogic.gdx.utils.viewport.FitViewport
import com.victorious.zombie.logic.Character
import com.victorious.zombie.net.ClientSession
import com.victorious.zombie.sim.Layout

/**
 * Waits for the host's WELCOME so the client knows which game the host runs (Zombie Survival or Blackout Royale),
 * then opens the matching screen. Gives up (and closes the link) after [TIMEOUT_S] or if the host refuses.
 */
class ConnectingScreen(private val character: Character, private val session: ClientSession, private val onFail: () -> Unit = {}) : ScreenAdapter() {
    private val cam = OrthographicCamera(); private val view = FitViewport(Layout.W, Layout.H, cam)
    private val batch = SpriteBatch(); private val font = BitmapFont()
    private var waited = 0f
    private var done = false
    private var failed = false

    override fun resize(width: Int, height: Int) { view.update(width, height, true) }

    override fun render(delta: Float) {
        if (done) return
        waited += delta
        if (!failed && session.playerId >= 0) { open(); return }
        if (!failed && (session.rejected || !session.connected || waited > TIMEOUT_S)) { failed = true; session.close() }
        if (failed && (Gdx.input.justTouched() || Gdx.input.isKeyJustPressed(Input.Keys.ENTER) || Gdx.input.isKeyJustPressed(Input.Keys.ESCAPE))) { leave(); return }
        Gdx.gl.glClearColor(0.03f, 0.02f, 0.06f, 1f); Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT)
        view.apply(); batch.projectionMatrix = cam.combined
        batch.begin(); font.color = if (failed) Color.YELLOW else Color.WHITE
        font.draw(batch, if (failed) "Could not join (host full, match already started, or not reachable). Tap to go back." else "Joining...", Layout.W / 2 - 220, Layout.H / 2)
        batch.end()
    }

    private fun open() {
        if (done) return
        done = true
        val game = Gdx.app.applicationListener as? VictorOpsGame
        game?.setScreen(if (session.kind == "royale") BrScreen(character, Mode.Client(session)) else GameScreen(character, Mode.Client(session)))
        dispose()
    }

    private fun leave() {
        if (done) return
        done = true
        onFail()
        (Gdx.app.applicationListener as? VictorOpsGame)?.setScreen(CharacterSelectScreen()); dispose()
    }

    override fun dispose() { batch.dispose(); font.dispose() }

    private companion object { const val TIMEOUT_S = 8f }
}
