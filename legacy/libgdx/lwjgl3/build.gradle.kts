plugins { kotlin("jvm"); application }
val gdxVersion: String by project
kotlin { jvmToolchain(17) }
dependencies {
    implementation(project(":core"))
    implementation("com.badlogicgames.gdx:gdx-backend-lwjgl3:$gdxVersion")
    implementation("com.badlogicgames.gdx:gdx-platform:$gdxVersion:natives-desktop")
}
application { mainClass.set("com.victorious.zombie.desktop.DesktopLauncherKt") }
tasks.named<JavaExec>("run") {
    workingDir = rootProject.file("assets")
    if (System.getProperty("os.name").lowercase().contains("mac")) jvmArgs("-XstartOnFirstThread")
}
