import java.util.Properties
import java.io.FileInputStream
import java.util.Base64

// Read a --dart-define value that Flutter encodes into the DART_DEFINES env var
// as a comma-separated list of base64(key=value) strings.
fun dartDefine(key: String, default: String = ""): String =
    (System.getenv("DART_DEFINES") ?: "")
        .split(",")
        .filter { it.isNotBlank() }
        .map { String(Base64.getDecoder().decode(it)) }
        .firstOrNull { it.startsWith("$key=") }
        ?.removePrefix("$key=")
        ?: default

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.gymcrm.gym_crm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.gymcrm.gym_crm"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Supabase credentials for the Kotlin SMS worker. Falls back to the
        // hardcoded production values when --dart-define is not passed (e.g.
        // local builds, CI without secrets). The anon key is a public key by
        // design — security comes from Supabase RLS policies, not key secrecy.
        val supabaseUrl = dartDefine("SUPABASE_URL")
            .ifBlank { "https://orlqjhqxeyukvfzsursl.supabase.co" }
        val supabaseAnonKey = dartDefine("SUPABASE_ANON_KEY")
            .ifBlank { "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9ybHFqaHF4ZXl1a3ZmenN1cnNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUzODM2NTgsImV4cCI6MjA5MDk1OTY1OH0.4JXUdbPTkofshaYaYSOJwE9qwQ2zwjUQljuu5cfgzzw" }
        buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrl\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseAnonKey\"")
    }

    signingConfigs {
        create("release") {
            if (keyPropertiesFile.exists()) {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.work:work-runtime-ktx:2.9.1")
}
