allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Every plugin module compiles with the same JVM target as :app.
//
// Older plugins (flutter_timezone 3.x, app_settings 5.x) still set Java 8/11
// and Kotlin 1.8 in their own build.gradle. Kotlin 2.x refuses to build a
// module whose Java and Kotlin tasks disagree, and we can't edit a pub-cache
// module, so the fix lives here. It has to run AFTER each plugin's own script
// (which is what sets the stale values) — hence afterEvaluate — but :app is
// already evaluated by the time this block runs (evaluationDependsOn above),
// so for an evaluated project the action runs immediately instead.
fun Project.appCompileSdk(): Int? =
    rootProject.project(":app").extensions.findByName("android")?.withGroovyBuilder {
        runCatching { getProperty("compileSdk") as? Int }.getOrNull()
    }

fun Project.alignJvmTargets(evaluated: Boolean) {
    // The android extension's compileOptions is what AGP feeds into the
    // JavaCompile tasks (in its own afterEvaluate), so set it at the source.
    // Looked up by name to avoid depending on the old-DSL extension class.
    // Not for a project that's already evaluated (:app): AGP has finalized
    // its compileOptions by then and refuses writes — and :app is 17 anyway.
    if (!evaluated) {
        extensions.findByName("android")?.withGroovyBuilder {
            val opts = getProperty("compileOptions")
            opts?.withGroovyBuilder {
                setProperty("sourceCompatibility", JavaVersion.VERSION_17)
                setProperty("targetCompatibility", JavaVersion.VERSION_17)
            }
            // Same story for compileSdk: a plugin still on 33 can't link
            // against the AndroidX versions the rest of the app pulls in
            // (AAR metadata check). Raise it to whatever :app compiles
            // against — never lower a plugin that's already ahead.
            val appSdk = appCompileSdk()
            val mine = runCatching { getProperty("compileSdk") as? Int }.getOrNull() ?: 0
            if (appSdk != null && mine < appSdk) setProperty("compileSdk", appSdk)
        }
    }
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
subprojects {
    if (state.executed) {
        alignJvmTargets(evaluated = true)
    } else {
        afterEvaluate { alignJvmTargets(evaluated = false) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
