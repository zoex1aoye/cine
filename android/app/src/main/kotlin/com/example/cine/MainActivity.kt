package com.example.cine

import android.app.ActivityManager
import android.content.Context
import android.media.MediaCodecList
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.cine/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMemoryInfo" -> {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val info = ActivityManager.MemoryInfo()
                        am.getMemoryInfo(info)
                        result.success(
                            mapOf(
                                "totalMem" to info.totalMem,
                                "availMem" to info.availMem,
                            ),
                        )
                    }
                    "hasHardwareVideoDecoder" -> {
                        val detail = probeDecoderDetail("video/avc")
                        val hevcDetail = probeDecoderDetail("video/hevc")
                        android.util.Log.i(
                            "CineHwdec",
                            "probe avc=$detail hevc=$hevcDetail api=${Build.VERSION.SDK_INT}",
                        )
                        result.success(
                            mapOf(
                                "h264" to (detail["hw"] as Boolean),
                                "hevc" to (hevcDetail["hw"] as Boolean),
                            ),
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasHardwareDecoder(mime: String): Boolean {
        return probeDecoderDetail(mime)["hw"] as Boolean
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
