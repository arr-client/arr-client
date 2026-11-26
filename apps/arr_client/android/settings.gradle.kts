pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.3.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
}

include(":app")

// Gradle refuses a project in a directory that it cannot write to, and the SDK's plugin of the
// integration tests is in one where the Flutter SDK is read-only, as under Nix (shell.nix). It is
// then built from a copy.
findProject(":integration_test")?.let { plugin ->
    if (!plugin.projectDir.canWrite()) {
        val copy = file("../build/integration_test_plugin")
        plugin.projectDir.copyRecursively(copy, overwrite = true)
        plugin.projectDir = copy
    }
}
