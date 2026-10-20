plugins { kotlin("jvm") }
val gdxVersion: String by project
kotlin { jvmToolchain(17) }
dependencies {
    api("com.badlogicgames.gdx:gdx:$gdxVersion")
    testImplementation(kotlin("test"))
    testImplementation("junit:junit:4.13.2")
}
tasks.test { useJUnit(); testLogging { events("passed", "failed") } }
