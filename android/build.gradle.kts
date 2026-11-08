import org.gradle.api.tasks.compile.JavaCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
    //tasks.withType<JavaCompile>().configureEach {
        // Prefer 'release' to keep flags consistent
    //    options.release.set(17)
        // (These are redundant with 'release' but harmless if you want them)
    //    sourceCompatibility = "17"
    //    targetCompatibility = "17"
    // }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
plugins {
    id("com.google.gms.google-services") version "4.4.3" apply false
}