plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ✅ Load dart-define values
val dartEnvironmentVariables = mutableMapOf<String, String>()

if (project.hasProperty("dart-defines")) {
    val dartDefines = project.property("dart-defines") as String
    dartDefines.split(",").forEach { entry ->
        val decoded = String(android.util.Base64.decode(entry, android.util.Base64.DEFAULT))
        val pair = decoded.split("=", limit = 2)
        if (pair.size == 2) {
            val key = pair[0]
            val lowercaseKey = key.lowercase()
            // Filter out Flutter framework variables
            if (!lowercaseKey.startsWith("flutter")) {
                dartEnvironmentVariables[key] = pair[1]
            }
        }
    }
}

android {
    namespace = "com.example.gigscourt"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.gigscourt"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ✅ Pass Google Maps API key to AndroidManifest.xml
        manifestPlaceholders["googleMapsApiKeyAndroid"] = dartEnvironmentVariables["GOOGLE_MAPS_API_KEY_ANDROID"] ?: ""
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
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