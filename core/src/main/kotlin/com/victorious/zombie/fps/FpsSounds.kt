package com.victorious.zombie.fps

import com.badlogic.gdx.Gdx
import com.badlogic.gdx.audio.Sound
import com.badlogic.gdx.utils.Disposable
import java.io.ByteArrayOutputStream
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Sound effects synthesised in code (no recorded or third-party audio). Each effect is generated once, cached as a small mono WAV in
 * local storage and loaded as a libGDX [Sound]. If audio is unavailable (no device, headless) the game simply stays silent.
 */
class FpsSounds : Disposable {
    private val sounds = HashMap<String, Sound>()
    var enabled = false; private set

    fun load() {
        try {
            for ((name, gen) in defs) {
                val f = Gdx.files.local("sfx/v1/$name.wav")
                if (!f.exists() || f.length() < 64) f.writeBytes(wav(gen()), false)
                sounds[name] = Gdx.audio.newSound(f)
            }
            enabled = true
        } catch (t: Throwable) {
            Gdx.app?.log("zombies", "sound disabled: ${t.message}")
        }
    }

    fun play(name: String, volume: Float = 1f, pitch: Float = 1f, pan: Float = 0f) {
        if (!enabled) return
        try { sounds[name]?.play(volume.coerceIn(0f, 1f), pitch.coerceIn(0.5f, 2f), pan.coerceIn(-1f, 1f)) } catch (_: Throwable) {}
    }

    override fun dispose() { sounds.values.forEach { try { it.dispose() } catch (_: Throwable) {} }; sounds.clear(); enabled = false }

    // ---- synthesis -----------------------------------------------------------------------------------------------------
    private companion object {
        const val RATE = 22050
        val rng = Random(7)

        fun buf(seconds: Float) = FloatArray((seconds * RATE).toInt())
        fun noise() = rng.nextFloat() * 2f - 1f

        /** One-pole low-pass in place; [k] 0..1 (smaller = darker). */
        fun lowpass(a: FloatArray, k: Float): FloatArray { var y = 0f; for (i in a.indices) { y += k * (a[i] - y); a[i] = y }; return a }
        fun normalize(a: FloatArray, peak: Float = 0.9f): FloatArray { var m = 1e-6f; for (v in a) m = max(m, kotlin.math.abs(v)); for (i in a.indices) a[i] = a[i] / m * peak; return a }

        fun shot(len: Float, crackTau: Float, boomTau: Float, thumpHz: Float, dark: Float, tail: Float = 0f): FloatArray {
            val a = buf(len); val b = buf(len)
            for (i in a.indices) { val t = i.toFloat() / RATE; a[i] = noise() * exp(-t / crackTau); b[i] = noise() * exp(-t / boomTau) }
            lowpass(b, dark)
            for (i in a.indices) {
                val t = i.toFloat() / RATE
                a[i] = a[i] * 0.55f + b[i] * 2.2f + sin(2 * PI.toFloat() * thumpHz * t) * exp(-t / 0.07f) * 0.8f
                if (tail > 0f) a[i] += noise() * 0.06f * exp(-t / tail)
            }
            return normalize(a)
        }

        fun tone(len: Float, vararg notes: Pair<Float, Float>): FloatArray { // (freq, start)
            val a = buf(len)
            for ((f, s) in notes) for (i in (s * RATE).toInt() until a.size) { val t = i.toFloat() / RATE - s; a[i] += sin(2 * PI.toFloat() * f * t) * exp(-t / 0.18f) * min(1f, t * 200f) }
            return normalize(a, 0.6f)
        }

        val defs: List<Pair<String, () -> FloatArray>> = listOf(
            "pistol" to { shot(0.35f, 0.012f, 0.06f, 90f, 0.25f) },
            "rifle" to { shot(0.5f, 0.015f, 0.1f, 70f, 0.2f, 0.25f) },
            "shotgun" to { shot(0.6f, 0.02f, 0.16f, 55f, 0.15f, 0.3f) },
            "smg" to { shot(0.22f, 0.008f, 0.04f, 110f, 0.3f) },
            "lmg" to { shot(0.3f, 0.01f, 0.07f, 75f, 0.22f) },
            "sniper" to { shot(0.9f, 0.02f, 0.14f, 50f, 0.12f, 0.5f) },
            "ray" to {
                val a = buf(0.45f)
                var ph = 0f
                for (i in a.indices) { val t = i.toFloat() / RATE; val f = 1400f * exp(-t * 7f) + 180f; ph += 2 * PI.toFloat() * f / RATE; a[i] = (sin(ph) + noise() * 0.35f * exp(-t * 10f)) * exp(-t * 4f) }
                normalize(a)
            },
            "hit" to { val a = buf(0.08f); for (i in a.indices) a[i] = noise() * exp(-i.toFloat() / RATE / 0.02f); normalize(lowpass(a, 0.12f), 0.7f) },
            "headshot" to { val a = buf(0.12f); for (i in a.indices) { val t = i.toFloat() / RATE; a[i] = noise() * exp(-t / 0.012f) + sin(2 * PI.toFloat() * 180f * t) * exp(-t / 0.04f) }; normalize(a, 0.8f) },
            "growl1" to { growl(0.9f, 72f, 1) }, "growl2" to { growl(1.1f, 60f, 2) }, "growl3" to { growl(0.8f, 88f, 3) },
            "board" to { val a = buf(0.2f); for (i in a.indices) { val t = i.toFloat() / RATE; a[i] = noise() * (exp(-t / 0.015f) + 0.4f * exp(-(t - 0.05f).coerceAtLeast(0f) / 0.03f) * (if (t > 0.05f) 1f else 0f)) }; normalize(lowpass(a, 0.5f)) },
            "fix" to { val a = buf(0.3f); for (i in a.indices) { val t = i.toFloat() / RATE; val t2 = (t - 0.14f).coerceAtLeast(0f); a[i] = sin(2 * PI.toFloat() * 130f * t) * exp(-t / 0.03f) + (if (t > 0.14f) sin(2 * PI.toFloat() * 120f * t2) * exp(-t2 / 0.03f) else 0f) }; normalize(a, 0.7f) },
            "buy" to { tone(0.5f, 880f to 0f, 1320f to 0.09f) },
            "deny" to { val a = buf(0.3f); for (i in a.indices) { val t = i.toFloat() / RATE; a[i] = (if (sin(2 * PI.toFloat() * 110f * t) > 0) 1f else -1f) * exp(-t / 0.15f) }; normalize(lowpass(a, 0.2f), 0.5f) },
            "round" to {
                val a = buf(3.2f)
                for (i in a.indices) { val t = i.toFloat() / RATE; val env = min(1f, t / 0.4f) * exp(-t / 1.4f); val trem = 0.75f + 0.25f * sin(2 * PI.toFloat() * 5f * t); a[i] = (sin(2 * PI.toFloat() * 55f * t) + 0.7f * sin(2 * PI.toFloat() * 82.4f * t) + 0.5f * sin(2 * PI.toFloat() * 110f * t) + 0.3f * sin(2 * PI.toFloat() * 116.5f * t)) * env * trem }
                normalize(a, 0.8f)
            },
            "roundend" to { val a = buf(2f); var ph = 0f; for (i in a.indices) { val t = i.toFloat() / RATE; ph += 2 * PI.toFloat() * (220f - 80f * t) / RATE; a[i] = (sin(ph) + 0.5f * sin(ph * 1.5f)) * min(1f, t * 10f) * exp(-t / 0.7f) }; normalize(a, 0.6f) },
            "powerup" to { tone(0.7f, 523f to 0f, 659f to 0.08f, 784f to 0.16f, 1046f to 0.24f) },
            "drop" to { tone(0.5f, 1046f to 0f, 1568f to 0.06f) },
            "power" to { val a = buf(2.6f); var ph = 0f; for (i in a.indices) { val t = i.toFloat() / RATE; ph += 2 * PI.toFloat() * (35f + 40f * min(1f, t / 1.5f)) / RATE; a[i] = (sin(ph) + 0.5f * sin(ph * 2f) + 0.25f * sin(ph * 3f)) * min(1f, t * 2f) * exp(-(t - 1.6f).coerceAtLeast(0f) / 0.4f) }; normalize(a, 0.8f) },
            "hurt" to { val a = buf(0.25f); for (i in a.indices) { val t = i.toFloat() / RATE; a[i] = noise() * exp(-t / 0.05f) + sin(2 * PI.toFloat() * 65f * t) * exp(-t / 0.08f) }; normalize(lowpass(a, 0.15f), 0.9f) },
            "reload" to { val a = buf(0.45f); for (i in a.indices) { val t = i.toFloat() / RATE; val t2 = (t - 0.3f).coerceAtLeast(0f); a[i] = noise() * exp(-t / 0.006f) + (if (t > 0.3f) noise() * exp(-t2 / 0.01f) * 1.3f else 0f) }; normalize(lowpass(a, 0.6f), 0.5f) },
            "knife" to { val a = buf(0.18f); for (i in a.indices) { val t = i.toFloat() / RATE; a[i] = noise() * sin(PI.toFloat() * t / 0.18f) }; val b = a.copyOf(); lowpass(b, 0.08f); for (i in a.indices) a[i] -= b[i]; normalize(lowpass(a, 0.35f), 0.5f) },
            "empty" to { val a = buf(0.05f); for (i in a.indices) a[i] = noise() * exp(-i.toFloat() / RATE / 0.004f); normalize(a, 0.4f) },
            "box" to { tone(1.6f, 784f to 0f, 659f to 0.2f, 988f to 0.4f, 784f to 0.6f, 1175f to 0.8f, 988f to 1.0f, 1568f to 1.25f) },
            "door" to { val a = buf(0.9f); for (i in a.indices) { val t = i.toFloat() / RATE; a[i] = noise() * min(1f, t * 8f) * exp(-t / 0.4f) * (0.6f + 0.4f * sin(2 * PI.toFloat() * 13f * t)) }; normalize(lowpass(a, 0.05f), 0.8f) },
        )

        fun growl(len: Float, base: Float, seed: Int): FloatArray {
            val r = Random(seed); val a = buf(len); var ph = 0f
            val wob = 2.5f + r.nextFloat() * 2f
            for (i in a.indices) {
                val t = i.toFloat() / RATE
                val f = base * (1f + 0.18f * sin(2 * PI.toFloat() * wob * t)) * (1f - 0.25f * t / len)
                ph += f / RATE
                val saw = (ph % 1f) * 2f - 1f
                val env = min(1f, t / 0.12f) * min(1f, (len - t) / 0.3f)
                a[i] = (saw * 0.7f + noise() * 0.5f) * env
            }
            return normalize(lowpass(a, 0.09f), 0.8f)
        }

        fun wav(samples: FloatArray): ByteArray {
            val data = ByteArray(samples.size * 2)
            for (i in samples.indices) { val v = (samples[i].coerceIn(-1f, 1f) * 32767f).toInt(); data[2 * i] = (v and 0xFF).toByte(); data[2 * i + 1] = ((v shr 8) and 0xFF).toByte() }
            val o = ByteArrayOutputStream(44 + data.size)
            fun i32(v: Int) { o.write(v and 0xFF); o.write((v shr 8) and 0xFF); o.write((v shr 16) and 0xFF); o.write((v shr 24) and 0xFF) }
            fun i16(v: Int) { o.write(v and 0xFF); o.write((v shr 8) and 0xFF) }
            o.write("RIFF".toByteArray()); i32(36 + data.size); o.write("WAVE".toByteArray())
            o.write("fmt ".toByteArray()); i32(16); i16(1); i16(1); i32(RATE); i32(RATE * 2); i16(2); i16(16)
            o.write("data".toByteArray()); i32(data.size); o.write(data)
            return o.toByteArray()
        }
    }
}
