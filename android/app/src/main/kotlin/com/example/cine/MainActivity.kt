package com.example.cine

import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.media.MediaCodecList
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), ComponentCallbacks2 {
    private val channelName = "com.example.cine/device"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getMemoryInfo" -> {
                    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val info = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(info)
                    result.success(
                        mapOf(
                            "totalMem" to info.totalMem,
                            "availMem" to info.availMem,
                            "lowRam" to am.isLowRamDevice,
                        ),
                    )
                }
                "hasHardwareVideoDecoder" -> {
                    result.success(hardwareVideoProbe)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        // 向 Flutter 侧通知 onTrimMemory 级别，以便主动释放图片与缓冲堆
        methodChannel?.invokeMethod("onTrimMemory", level)
    }

    override fun onLowMemory() {
        super.onLowMemory()
        methodChannel?.invokeMethod("onLowMemory", null)
    }

    /** 枚举 MediaCodecList 较慢（低端 TV 上可达上百毫秒），只在首次调用时扫描。 */
    private val hardwareVideoProbe: Map<String, Boolean> by lazy {
        val avc = probeDecoderDetail("video/avc")
        val hevc = probeDecoderDetail("video/hevc")
        android.util.Log.i(
            "CineHwdec",
            "probe avc=$avc hevc=$hevc api=${Build.VERSION.SDK_INT}",
        )
        mapOf(
            "h264" to (avc["hw"] as Boolean),
            "hevc" to (hevc["hw"] as Boolean),
        )
    }

    /** Returns map: hw (bool), names (comma-separated), count (int). */
    private fun probeDecoderDetail(mime: String): Map<String, Any> {
        val names = mutableListOf<String>()
        var hw = false
        val list = MediaCodecList(MediaCodecList.ALL_CODECS)
        for (info in list.codecInfos) {
            if (info.isEncoder) continue
            val supports = info.supportedTypes.any { it.equals(mime, ignoreCase = true) }
            if (!supports) continue
            val name = info.name
            val swOnly = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                info.isSoftwareOnly
            } else {
                isGoogleSoftwareCodec(name)
            }
            val hwAcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                info.isHardwareAccelerated
            } else {
                !isGoogleSoftwareCodec(name)
            }
            names.add("$name(swOnly=$swOnly,hwAcc=$hwAcc)")
            if (isGoogleSoftwareCodec(name)) continue
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (hwAcc || !swOnly) hw = true
            } else {
                hw = true
            }
        }
        return mapOf(
            "hw" to hw,
            "count" to names.size,
            "names" to names.joinToString(" | "),
        )
    }

    private fun isGoogleSoftwareCodec(name: String): Boolean {
        val n = name.lowercase()
        return n.contains("omx.google") ||
            n.contains("c2.android") ||
            n.startsWith("c2.google")
    }
}
