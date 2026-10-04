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
            // ABI 由 flutter --target-platform 决定。这里不能写 abiFilters：
            // 电视构建开了 --split-per-abi 时，splits 是工程级的，任何 flavor 上的
            // abiFilters 都会和它冲突。手机 workflow 只传 android-arm64。
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
