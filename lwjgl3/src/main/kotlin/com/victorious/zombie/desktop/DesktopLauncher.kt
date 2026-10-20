package com.victorious.zombie.desktop

import com.badlogic.gdx.backends.lwjgl3.Lwjgl3Application
import com.badlogic.gdx.backends.lwjgl3.Lwjgl3ApplicationConfiguration
import com.victorious.zombie.VictorOpsGame

fun main() {
    val cfg = Lwjgl3ApplicationConfiguration().apply {
        setTitle("VictorOps Zombies"); setWindowedMode(1280, 720); useVsync(true); setForegroundFPS(60)
    }
    Lwjgl3Application(VictorOpsGame(), cfg)
}
