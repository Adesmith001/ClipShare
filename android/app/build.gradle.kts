import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val storeBeta = (project.findProperty("dart-defines") as? String).orEmpty().split(",").any {
    runCatching { String(Base64.getDecoder().decode(it)) == "STORE_BETA=true" }.getOrDefault(false)
}

// Local properties take precedence; CI may provide the same values through env.
val releaseKeys = Properties().apply {
    val propertiesFile = rootProject.file(if (storeBeta) "key.beta.properties" else "key.properties")
    if (propertiesFile.isFile) propertiesFile.inputStream().use { load(it) }
}
fun releaseKey(property: String, environment: String): String? =
    (releaseKeys.getProperty(property) ?: System.getenv(environment))?.takeIf { it.isNotBlank() }
val releaseStore = releaseKey("storeFile", "CLIPSHARE_STORE_FILE")?.let(rootProject::file)
val releaseStorePassword = releaseKey("storePassword", "CLIPSHARE_STORE_PASSWORD")
val releaseAlias = releaseKey("keyAlias", "CLIPSHARE_KEY_ALIAS")
val releaseKeyPassword = releaseKey("keyPassword", "CLIPSHARE_KEY_PASSWORD")
val releaseSigningReady = releaseStore?.isFile == true && releaseStorePassword != null &&
    releaseAlias != null && releaseKeyPassword != null

gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("release", ignoreCase = true) } &&
        !releaseSigningReady) {
        throw GradleException("Release signing is missing. Configure android/key.properties (see key.properties.example) or CLIPSHARE_STORE_FILE, CLIPSHARE_STORE_PASSWORD, CLIPSHARE_KEY_ALIAS and CLIPSHARE_KEY_PASSWORD. A release keystore file must exist.")
    }
}


android {
    namespace = "com.adesmith001.clipshare"
    buildFeatures { buildConfig = true }
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (storeBeta) "com.adesmith001.clipshare.beta" else "com.adesmith001.clipshare"
        buildConfigField("boolean", "STORE_BETA", storeBeta.toString())
        manifestPlaceholders["appLabel"] = if (storeBeta) "ClipShare Beta" else "ClipShare"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "android.test.InstrumentationTestRunner"
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = releaseStore
                storePassword = releaseStorePassword
                keyAlias = releaseAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
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

// The platform test runner lives in an optional SDK library on current Android.
// Compile-only keeps these platform classes out of both APKs.
dependencies {
    implementation("com.google.android.play:app-update:2.1.0")
    androidTestCompileOnly(files("${android.sdkDirectory}/platforms/android-${android.compileSdk}/optional/android.test.base.jar"))
}
