plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.arrclient.app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Cannot change once published (docs/decisions.md).
        applicationId = "io.github.arrclient.app"
        minSdk = 26
        targetSdk = 37
        // Both come from `version` in pubspec.yaml.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release builds have no signing config yet, so they come out unsigned rather than signed
    // with the debug key.
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
