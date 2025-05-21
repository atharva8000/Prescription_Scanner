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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

android {
    compileSdk = 33

    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.example.med_reminder_app"
        minSdk = 21
        targetSdk = 33
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }
}

