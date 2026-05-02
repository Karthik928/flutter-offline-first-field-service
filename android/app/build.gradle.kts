plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("kotlin-kapt")
}

import java.util.Properties
import java.io.FileInputStream

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}


android {
    namespace = "com.FieldServiceBioRemedies.FieldService_app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
    isCoreLibraryDesugaringEnabled = true

    }
kotlinOptions { jvmTarget = "17" }


    defaultConfig {
        applicationId = "com.FieldServiceBioRemedies.FieldService_app"
        minSdk = 24                      
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        manifestPlaceholders["MAPS_API_KEY"] = "YOUR_GOOGLE_MAPS_API_KEY"
    }

    signingConfigs {
    create("release") {
        keyAlias = keystoreProperties["keyAlias"] as String
        keyPassword = keystoreProperties["keyPassword"] as String
        storeFile = file(keystoreProperties["storeFile"] as String)
        storePassword = keystoreProperties["storePassword"] as String
    }
}
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
        isMinifyEnabled = false
        isShrinkResources = false
    }
}


}

flutter { source = "../.." }

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.3.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-messaging")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5") // ← updated
    
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Google Play Services Location
    implementation("com.google.android.gms:play-services-location:21.0.1")

    // Room Database
    val roomVersion = "2.7.2"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    kapt("androidx.room:room-compiler:$roomVersion")

    // Kotlin Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.7.3")

    // Lifecycle (for LifecycleService)
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-service:2.7.0")

    // WorkManager for resilient background job scheduling
    implementation("androidx.work:work-runtime-ktx:2.8.1")
}
