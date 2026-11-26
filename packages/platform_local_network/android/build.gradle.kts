group = "io.github.arrclient.localnetwork"

// Built as part of the app, whose settings file pins the plugin versions.
plugins {
    id("com.android.library")
}

android {
    namespace = "io.github.arrclient.localnetwork"
    compileSdk = 37

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 26
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
