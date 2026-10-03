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
        // 默认保留 arm64-v8a；低端 1GB 电视若为 32位固件，可通过 -Ptarget-platform=android-arm 打 armeabi-v7a
        // 不认识的取值一律忽略，全部无效时回落 arm64-v8a，避免产出空 ABI 的包。
        val abiByPlatform = mapOf(
            "android-arm" to "armeabi-v7a",
            "android-arm64" to "arm64-v8a",
            "android-x64" to "x86_64",
        )
        val targetAbis = (project.findProperty("target-platform") as? String)
            ?.split(",")
            ?.mapNotNull { abiByPlatform[it.trim()] }
            ?.takeIf { it.isNotEmpty() }
            ?: listOf("arm64-v8a")
        ndk {
            abiFilters.clear()
            abiFilters += targetAbis
        }
    }

    // mobile = phone/tablet；tv = projector/Android TV sideload（Leanback required=false）
    // 构建须带 --flavor，并同步 --dart-define=CINE_SURFACE=mobile|tv
    flavorDimensions += "surface"
    productFlavors {
        create("mobile") {
            dimension = "surface"
        }
        create("tv") {
            dimension = "surface"
            applicationIdSuffix = ".tv"
            resValue("string", "app_name", "幕布 TV")
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
            val abi = output.filters.find { it.filterType == "ABI" }?.identifier ?: "universal"
            val surface = variant.flavorName.ifEmpty { "mobile" }
            output.outputFileName = "mubu_${variant.versionName}_${surface}_${abi}.apk"
        }
    }
}

flutter {
    source = "../.."
}
