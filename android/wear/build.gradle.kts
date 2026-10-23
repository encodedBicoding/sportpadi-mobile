// SportPadi Watch — Wear OS (docs/design/watch-officiant.md; README.md here).
// Same applicationId and signing as :app — required for the Data Layer
// pairing — uploaded to Play as the Wear APK of the same listing.
@file:Suppress("DEPRECATION_ERROR", "DEPRECATION")

import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.sportpadi.watch"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.sportpadi.app"
        minSdk = 30            // Wear OS 3+
        targetSdk = 35
        // Keep in step with :app (pubspec version); Play needs the Wear APK's
        // versionCode to differ from the phone APK's — hence the offset.
        versionCode = 20_000_000 + (findProperty("wearVersionCode")?.toString()?.toIntOrNull() ?: 1)
        versionName = findProperty("wearVersionName")?.toString() ?: "1.0.0"
    }

    val keystoreProperties = Properties()
    val keystoreFile = rootProject.file("key.properties")
    if (keystoreFile.exists()) keystoreFile.inputStream().use { keystoreProperties.load(it) }
    signingConfigs {
        if (keystoreFile.exists()) {
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
            signingConfig = if (keystoreFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
}

kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.compose.ui:ui:1.7.6")
    implementation("androidx.compose.foundation:foundation:1.7.6")
    implementation("androidx.wear.compose:compose-material:1.4.0")
    implementation("androidx.wear.compose:compose-foundation:1.4.0")
    implementation("androidx.wear.compose:compose-navigation:1.4.0")
    implementation("androidx.wear:wear:1.3.0")            // AmbientLifecycleObserver
    implementation("androidx.wear:wear-ongoing:1.0.0")    // OngoingActivity (clock on the watch face)
    implementation("com.google.android.gms:play-services-wearable:18.2.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
