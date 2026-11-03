import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// R29 (signing pipeline): production release signing. The keystore is THE app's
// lifetime key — an update must be signed with the same certificate as the published
// 4.1.2 build (CN=NuBLime VPN, SHA-256 08:52:56:3A…), otherwise Android refuses the
// in-place upgrade. Credentials live in android/key.properties (gitignored).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.nublime.vpn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nublime.vpn"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // FAIL-CLOSED: a release build without the production keystore must not
            // exist. Shipping a debug-signed "release" would silently break every
            // future in-place upgrade (signature mismatch), so the build stops here.
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "Release signing is not configured: create android/key.properties " +
                        "(storeFile/keyAlias/storePassword/keyPassword) — the production " +
                        "keystore is the app's lifetime signing key."
                )
            }
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // Release ships arm64 only. The libXray AAR carries four ABIs of libgojni.so (~103 MB
    // uncompressed); packaging all of them produced a 162.8 MB APK whose x86/x86_64/armv7
    // slices can never run on the target device class. `ndk.abiFilters` does NOT filter
    // prebuilt .so coming from a dependency AAR, so the exclusion has to happen at packaging
    // level. Debug builds keep x86_64 so emulator testing still works.
    packaging {
        jniLibs {
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86/**")
            excludes += if (gradle.startParameter.taskNames.any { it.contains("Debug", ignoreCase = true) }) {
                emptyList()
            } else {
                listOf("lib/x86_64/**")
            }
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

// libXray (Xray-core gomobile bindings) + hev-socks5-tunnel native libs
dependencies {
    implementation(files("libs/libXray.aar"))
}
