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

// Force all library subprojects to compile against SDK 36.
// Required because flutter_webrtc (transitive dep) needs compileSdk 36,
// but livekit_client ships with compileSdk 34.
subprojects {
    if (project.name != "app") {
        project.afterEvaluate {
            if (project.plugins.hasPlugin("com.android.library")) {
                project.extensions.configure<com.android.build.gradle.LibraryExtension> {
                    compileSdk = 36
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
