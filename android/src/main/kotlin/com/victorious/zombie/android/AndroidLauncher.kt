package com.victorious.zombie.android

import android.os.Bundle
import com.badlogic.gdx.backends.android.AndroidApplication
import com.badlogic.gdx.backends.android.AndroidApplicationConfiguration
import com.victorious.zombie.VictorOpsGame

class AndroidLauncher : AndroidApplication() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialize(VictorOpsGame(), AndroidApplicationConfiguration().apply { useImmersiveMode = true })
    }
}
