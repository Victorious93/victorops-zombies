import java.util.Properties

plugins { id("com.android.application"); kotlin("android") }
val gdxVersion: String by project
val natives: Configuration by configurations.creating

val vozFileProps = Properties().apply {
    listOf("keystore.properties", "local.properties").map { rootProject.file(it) }.filter { it.exists() }
        .forEach { f -> f.inputStream().use { load(it) } }
}
fun vozProp(name: String): String? = System.getenv(name)?.takeIf { it.isNotBlank() } ?: vozFileProps.getProperty(name)
val vozKeystore: String? = vozProp("VOZ_KEYSTORE_PATH")?.takeIf { file(it).exists() }

android {
    namespace = "com.victorious.zombie"
    compileSdk = 35
    buildToolsVersion = "35.0.0"
    defaultConfig {
        applicationId = "com.victorious.zombie"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
    }
    signingConfigs {
        // Signing values come from env vars or git-ignored keystore.properties / local.properties.
        // If none are set, AGP's default ~/.android/debug.keystore is used so a fresh clone still builds.
        if (vozKeystore != null) {
            create("voz") {
                storeFile = file(vozKeystore)
                storePassword = vozProp("VOZ_KEYSTORE_PASSWORD")
                keyAlias = vozProp("VOZ_KEY_ALIAS")
                keyPassword = vozProp("VOZ_KEY_PASSWORD")
                enableV1Signing = true; enableV2Signing = true; enableV3Signing = true
            }
        }
        getByName("debug") { enableV1Signing = true; enableV2Signing = true; enableV3Signing = true }
    }
    buildTypes {
        getByName("debug") { signingConfig = signingConfigs.findByName("voz") ?: signingConfigs.getByName("debug") }
        getByName("release") { isMinifyEnabled = false } // release signing configured outside repo
    }
    sourceSets["main"].apply {
        assets.srcDirs(rootProject.file("assets"))
        jniLibs.srcDirs("libs")
        res.srcDirs("res")
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    packaging { jniLibs { useLegacyPackaging = true } }
}
kotlin { jvmToolchain(17) }

dependencies {
    implementation(project(":core"))
    implementation("com.badlogicgames.gdx:gdx-backend-android:$gdxVersion")
    natives("com.badlogicgames.gdx:gdx-platform:$gdxVersion:natives-armeabi-v7a")
    natives("com.badlogicgames.gdx:gdx-platform:$gdxVersion:natives-arm64-v8a")
}

val copyAndroidNatives by tasks.registering {
    doFirst {
        natives.files.forEach { jar ->
            val abi = jar.nameWithoutExtension.substringAfter("natives-")
            val outDir = file("libs/$abi").apply { mkdirs() }
            copy { from(zipTree(jar)); into(outDir); include("*.so") }
        }
    }
}
tasks.matching { it.name.contains("merge") && it.name.contains("JniLibFolders") }.configureEach { dependsOn(copyAndroidNatives) }
tasks.named("preBuild") { dependsOn(copyAndroidNatives) }
