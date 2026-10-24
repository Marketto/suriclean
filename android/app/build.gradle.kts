plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The release workflow passes SURI_VERSION=1.N; N becomes the versionCode so updates always go up.
val suriVersion: String = System.getenv("SURI_VERSION") ?: "1.0"
val suriCode: Int = suriVersion.substringAfter(".").toIntOrNull() ?: 1
val keystorePath: String? = System.getenv("SURI_KEYSTORE")

android {
    namespace = "com.suriclean.app"
    compileSdk = 34

    // «Arcade Sparkle» for the remix, shared with the Mac, desktop and web versions
    sourceSets["main"].assets.srcDir("../../shared/audio")

    defaultConfig {
        applicationId = "com.suriclean.app"
        minSdk = 26
        targetSdk = 34
        versionCode = suriCode
        versionName = suriVersion
    }

    signingConfigs {
        create("release") {
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storeType = "pkcs12"
                storePassword = System.getenv("SURI_KEYSTORE_PASSWORD")
                keyAlias = "suriclean"
                keyPassword = System.getenv("SURI_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (keystorePath != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.00")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.6")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
}
