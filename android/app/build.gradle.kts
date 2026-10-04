plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.cine"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.cine"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // mobile = phone/tablet；tv = projector/Android TV sideload（Leanback required=false）
    // 构建须带 --flavor，并同步 --dart-define=CINE_SURFACE=mobile|tv
    flavorDimensions += "surface"
    productFlavors {
        create("mobile") {
            dimension = "surface"
            // 手机保持 arm64，避免多 ABI 包在部分天玑机上抽到 v7a 兼容库
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
        }
        create("tv") {
            dimension = "surface"
            applicationIdSuffix = ".tv"
            resValue("string", "app_name", "幕布 TV")
            // 不要在这里写 abiFilters。workflow 用 --split-per-abi 打 v7a 与 arm64，
            // AGP 不允许 abiFilters 和 splits 同时存在。
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    applicationVariants.all {
        val variant = this
        variant.outputs.all {
            val output = this as com.android.build.gradle.api.ApkVariantOutput
            val abiFromOutput = output.filters.find { it.filterType == "ABI" }?.identifier
            val abi = abiFromOutput
                ?: if (variant.flavorName == "mobile") "arm64-v8a" else "universal"
            val surface = variant.flavorName.ifEmpty { "mobile" }
            output.outputFileName = "mubu_${variant.versionName}_${surface}_${abi}.apk"
        }
    }
}

flutter {
    source = "../.."
}
