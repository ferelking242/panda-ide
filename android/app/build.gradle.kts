import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.panda.ide"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.panda.ide"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // NOTE: ndk.abiFilters retiré intentionnellement — le workflow CI passe
        // --target-platform android-arm64 --split-per-abi qui gère le filtrage
        // via Flutter. Les deux en même temps causent un conflit Gradle.
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use release signing if key.properties exists, otherwise debug signing (CI)
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"    
            )
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            pickFirsts += listOf(
                "lib/arm64-v8a/libc++_shared.so",
            )
            excludes += setOf("**/armeabi-v7a/**", "**/x86_64/**")
        }
    }

    dynamicFeatures.addAll(
        setOf(
            ":app:rust_feature",
            ":app:go_feature",
            ":app:ruby_feature",
            ":app:lua_feature",
            ":app:node_feature",
            ":app:python_feature",
            ":app:java_feature",
            ":app:kotlin_feature",
            ":app:clang_feature",
            ":app:dart_feature",
            ":app:ty_feature",
            ":app:rust_analyzer_feature",
            ":app:gopls_feature",
            ":app:emmylua_feature",
            ":app:bash_language_server_feature",
            ":app:copilot_language_server_feature",
            ":app:kmp_lsp_feature",
            ":app:vscode_langservers_extracted_feature",
        )
    )
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}


dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("com.google.android.play:feature-delivery:2.1.0")
    // Shizuku — ADB-level shell access without root (flutter run on-device)
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
}


flutter {
    source = "../.."
}
