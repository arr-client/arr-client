import java.util.Properties

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

    // Release builds are signed with the key that android/key.properties names (see
    // CONTRIBUTING.md). Without that file they come out unsigned, never signed with the debug key.
    val keyPropertiesFile = rootProject.file("key.properties")
    if (keyPropertiesFile.exists()) {
        val keyProperties = Properties()
        keyPropertiesFile.reader().use { keyProperties.load(it) }
        val names = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        val missing = names.filter { keyProperties.getProperty(it).isNullOrBlank() }
        if (missing.isNotEmpty()) {
            throw GradleException("$keyPropertiesFile has no value for: ${missing.joinToString()}")
        }
        // A relative path starts at android/app.
        val keystore = file(keyProperties.getProperty("storeFile"))
        if (!keystore.isFile) {
            throw GradleException("$keyPropertiesFile: there is no keystore at $keystore")
        }
        val releaseKey =
            signingConfigs.create("release") {
                storeFile = keystore
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        buildTypes.getByName("release") { signingConfig = releaseKey }
    }
}

// The in-app license page carries a notice for each library in ../release_dependencies.txt, so the
// build fails when the release APK gains, loses or updates a library.
androidComponents {
    onVariants(selector().withName("release")) { variant ->
        val classpath = variant.runtimeConfiguration.incoming.resolutionResult.rootComponent
        val list = rootProject.file("release_dependencies.txt")
        val listCheck =
            tasks.register("checkReleaseDependencies") {
                doLast {
                    val seen = mutableSetOf<ResolvedComponentResult>()
                    fun visit(component: ResolvedComponentResult) {
                        if (!seen.add(component)) return
                        component.dependencies
                            .filterIsInstance<ResolvedDependencyResult>()
                            .filterNot { it.isConstraint }
                            .forEach { visit(it.selected) }
                    }
                    visit(classpath.get())
                    val unresolved =
                        seen.flatMap { it.dependencies }.filterIsInstance<UnresolvedDependencyResult>()
                    check(unresolved.isEmpty()) {
                        "Unresolved dependencies: ${unresolved.map { it.requested }}"
                    }
                    val shipped =
                        seen
                            .mapNotNull { it.id as? ModuleComponentIdentifier }
                            .filter { it.group != "io.flutter" }
                            .map { "${it.group}:${it.module}:${it.version}" }
                            .toSet()
                    val listed =
                        list
                            .readLines()
                            .filter { it.isNotBlank() && !it.startsWith("#") }
                            .map { it.substringBefore(' ') }
                            .toSet()
                    if (shipped != listed) {
                        throw GradleException(
                            "$list does not match the release runtime classpath.\n" +
                                "Not listed: ${(shipped - listed).sorted()}\n" +
                                "No longer used: ${(listed - shipped).sorted()}\n" +
                                "Read the top of that file before changing it.",
                        )
                    }
                }
            }
        // Debug builds too, so that CI sees a change without a release build.
        tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(listCheck) }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
