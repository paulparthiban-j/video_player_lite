import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties (git-ignored), or from
// environment variables in CI (see .github/workflows/release.yml):
//   storeFile=/absolute/path/to/upload-keystore.jks
//   storePassword=...
//   keyAlias=upload
//   keyPassword=...
// Without either, release builds fall back to the debug key so local
// `flutter run --release` keeps working; such builds cannot be published.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
    System.getenv("ANDROID_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }?.let {
        setProperty("storeFile", it)
        setProperty("storePassword", System.getenv("ANDROID_KEYSTORE_PASSWORD"))
        setProperty("keyAlias", System.getenv("ANDROID_KEY_ALIAS"))
        setProperty("keyPassword", System.getenv("ANDROID_KEY_PASSWORD"))
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.parthi.play"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources {
            pickFirsts += listOf("**/libc++_shared.so", "**/libjsc.so")
            excludes += listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/ASL2.0",
            )
        }
        jniLibs {
            // Store native libraries uncompressed and page-aligned so the app
            // loads on devices with 16 KB memory pages (Android 15+).
            useLegacyPackaging = false
        }
    }

    defaultConfig {
        applicationId = "com.parthi.play"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("No release keystore configured: signing release with the debug key")
                signingConfigs.getByName("debug")
            }

            // Flutter apps can break with R8/resource shrinking in release;
            // keep them off unless fully audited with proper keep rules.
            isMinifyEnabled = false
            isShrinkResources = false

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Play Store delivers per-ABI/density/language splits from the bundle.
    bundle {
        language { enableSplit = true }
        density { enableSplit = true }
        abi { enableSplit = true }
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
