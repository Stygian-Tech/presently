plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.kapt")
    id("androidx.room")
}

fun releaseValue(gradleProperty: String, environmentVariable: String) =
    providers.gradleProperty(gradleProperty)
        .orElse(providers.environmentVariable(environmentVariable))

val releaseVersionCode =
    releaseValue("presentlyVersionCode", "PRESENTLY_VERSION_CODE")
        .orElse("1")
        .map { value ->
            value.toIntOrNull()?.takeIf { it > 0 }
                ?: error("Presently versionCode must be a positive integer, but was '$value'.")
        }

val releaseVersionName =
    releaseValue("presentlyVersionName", "PRESENTLY_VERSION_NAME")
        .orElse("0.1.0")

val releaseStoreFile =
    releaseValue("presentlyUploadStoreFile", "PRESENTLY_UPLOAD_STORE_FILE")
val releaseStorePassword =
    releaseValue("presentlyUploadStorePassword", "PRESENTLY_UPLOAD_STORE_PASSWORD")
val releaseKeyAlias =
    releaseValue("presentlyUploadKeyAlias", "PRESENTLY_UPLOAD_KEY_ALIAS")
val releaseKeyPassword =
    releaseValue("presentlyUploadKeyPassword", "PRESENTLY_UPLOAD_KEY_PASSWORD")

val releaseSigningValues =
    listOf(
        releaseStoreFile,
        releaseStorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    )
val releaseSigningConfigured =
    releaseSigningValues.all { value -> value.isPresent && value.get().isNotBlank() }

android {
    namespace = "tech.stygian.presently"
    compileSdk = 36

    defaultConfig {
        applicationId = "tech.stygian.presently"
        minSdk = 23
        targetSdk = 36
        versionCode = releaseVersionCode.get()
        versionName = releaseVersionName.get()

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile.get())
                storePassword = releaseStorePassword.get()
                keyAlias = releaseKeyAlias.get()
                keyPassword = releaseKeyPassword.get()
            }
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.browser:browser:1.8.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.0")

    implementation(platform("androidx.compose:compose-bom:2025.05.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.material3:material3")
    implementation("io.coil-kt:coil-compose:2.7.0")
    debugImplementation("androidx.compose.ui:ui-tooling")

    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
    implementation("androidx.camera:camera-view:1.4.2")
    implementation("androidx.exifinterface:exifinterface:1.4.1")

    implementation("androidx.room:room-runtime:2.7.1")
    implementation("androidx.room:room-ktx:2.7.1")
    kapt("androidx.room:room-compiler:2.7.1")
    kaptTest("androidx.room:room-compiler:2.7.1")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
    testImplementation("org.json:json:20250517")
}

room {
    schemaDirectory("$projectDir/schemas")
}

kapt {
    correctErrorTypes = true
}

tasks.matching { task ->
    task.name == "bundleRelease" || task.name == "assembleRelease"
}.configureEach {
    doFirst {
        check(releaseSigningConfigured) {
            "Release signing is not configured. Set PRESENTLY_UPLOAD_STORE_FILE, " +
                "PRESENTLY_UPLOAD_STORE_PASSWORD, PRESENTLY_UPLOAD_KEY_ALIAS, and " +
                "PRESENTLY_UPLOAD_KEY_PASSWORD (or their Gradle property equivalents)."
        }
        check(rootProject.file(releaseStoreFile.get()).isFile) {
            "The configured Presently upload keystore does not exist."
        }
    }
}
