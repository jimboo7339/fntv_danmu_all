package com.fntv.fnos_tv_all

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import androidx.media3.common.util.UnstableApi

@UnstableApi
class ExoPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.fntv.fnos_tv_all/exo_player")
        channel.setMethodCallHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            "exo_player_view",
            ExoPlayerViewFactory(binding.binaryMessenger),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "create" -> {
                    val playerId = call.argument<Int>("playerId") ?: 0
                    ExoPlayerManager.create(context, playerId)
                    result.success(null)
                }
                "setSource" -> {
                    val playerId = call.argument<Int>("playerId") ?: 0
                    val url = call.argument<String>("url") ?: ""
                    @Suppress("UNCHECKED_CAST")
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    val startMs = (call.argument<Number>("startMs") ?: 0).toLong()
                    ExoPlayerManager.setSource(context, playerId, url, headers, startMs)
                    result.success(null)
                }
                "play" -> {
                    ExoPlayerManager.play(call.argument<Int>("playerId") ?: 0)
                    result.success(null)
                }
                "pause" -> {
                    ExoPlayerManager.pause(call.argument<Int>("playerId") ?: 0)
                    result.success(null)
                }
                "seek" -> {
                    ExoPlayerManager.seek(
                        call.argument<Int>("playerId") ?: 0,
                        (call.argument<Number>("positionMs") ?: 0).toLong(),
                    )
                    result.success(null)
                }
                "setSpeed" -> {
                    ExoPlayerManager.setSpeed(
                        call.argument<Int>("playerId") ?: 0,
                        (call.argument<Double>("speed") ?: 1.0).toFloat(),
                    )
                    result.success(null)
                }
                "setSubtitleTrack" -> {
                    ExoPlayerManager.setSubtitleTrack(
                        call.argument<Int>("playerId") ?: 0,
                        call.argument<Int>("trackIndex") ?: -1,
                    )
                    result.success(null)
                }
                "setAudioTrack" -> {
                    ExoPlayerManager.setAudioTrack(
                        call.argument<Int>("playerId") ?: 0,
                        call.argument<Int>("trackIndex") ?: 0,
                    )
                    result.success(null)
                }
                "getState" -> {
                    result.success(ExoPlayerManager.getState(call.argument<Int>("playerId") ?: 0))
                }
                "dispose" -> {
                    ExoPlayerManager.dispose(call.argument<Int>("playerId") ?: 0)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("exo_error", e.message, null)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivity() {}
}
