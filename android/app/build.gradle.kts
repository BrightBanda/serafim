import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. android/key.properties (gitignored) points at the keystore;
// without it the release build falls back to the debug key, so a fresh clone
// can still `flutter run --release`. See docs/firebase-setup.md.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keyProperties.containsKey("storeFile")

android {
    namespace = "com.binaryforge.serafim"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Must never change again: in-app updates only install over the same
        // application id signed with the same key.
        applicationId = "com.binaryforge.serafim"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Shrink and optimise code and resources: smaller APK.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Release builds contain native libraries for the CPU types being built
// (`flutter build apk --target-platform ...`) and nothing else. The Flutter
// plugin lists every ABI in defaultConfig, so plugins would otherwise still
// pack their 32-bit/x86 libraries, and an APK could install on phones it can't
// run on. tool/release.sh builds one APK for arm64 + 32-bit ARM. Debug builds
// keep every ABI so emulators work.
val flutterAbis = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x64" to "x86_64",
)
val builtAbis = (project.findProperty("target-platform") as String?)
    ?.split(",")
    ?.mapNotNull { flutterAbis[it.trim()] }
    ?.toSet()
    ?.takeIf { it.isNotEmpty() }
    ?: setOf("arm64-v8a")

androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        val unwanted = listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64") - builtAbis
        variant.packaging.jniLibs.excludes.addAll(unwanted.map { "lib/$it/**" })
    }
}

flutter {
    source = "../.."
}
