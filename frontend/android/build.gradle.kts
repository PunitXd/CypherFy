allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Build output location.
//
// Defaults to <project>/build. Set CYPHERFY_BUILD_DIR to an absolute path to
// put intermediates elsewhere — required when the repo lives on a filesystem
// without native extended-attribute support (exFAT/FAT external volumes on
// macOS). There, every file carrying an xattr gets a companion AppleDouble
// "._name" sidecar, and AGP's class-jar step globs `**/*.class`, sweeping
// `._Foo.class` into the jar. Kotlin's incremental compiler then hands that
// 4KB sidecar to ASM, which rejects it with a bare IllegalArgumentException.
// Building on an APFS/HFS+ path avoids the sidecars being created at all.
val envBuildDir: String? = System.getenv("CYPHERFY_BUILD_DIR")
val newBuildDir: Directory =
    if (!envBuildDir.isNullOrBlank()) {
        rootProject.layout.projectDirectory.dir(envBuildDir)
    } else {
        rootProject.layout.buildDirectory
            .dir("../../build")
            .get()
    }
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
