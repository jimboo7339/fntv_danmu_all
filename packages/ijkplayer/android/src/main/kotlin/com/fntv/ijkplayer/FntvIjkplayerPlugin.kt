package com.fntv.ijkplayer

import android.os.Handler
import android.os.Looper
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import tv.danmaku.ijk.media.player.IjkMediaPlayer

class FntvIjkplayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var player: IjkMediaPlayer? = null
    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private val handler = Handler(Looper.getMainLooper())
    private var pollRunnable: Runnable? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        channel = MethodChannel(binding.binaryMessenger, "fntv_ijkplayer")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        release()
        this.binding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> create(result)
            "setDataSource" -> {
                val url = call.argument<String>("url")!!
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                val seekMs = call.argument<Int>("seekMs") ?: 0
                setDataSource(url, headers, seekMs, result)
            }
            "play" -> { player?.start(); result.success(null) }
            "pause" -> { player?.pause(); result.success(null) }
            "seekTo" -> {
                val ms = call.argument<Int>("positionMs")!!
                player?.seekTo(ms.toLong())
                result.success(null)
            }
            "setSpeed" -> {
                val speed = call.argument<Double>("speed")!!
                player?.setSpeed(speed.toFloat())
                result.success(null)
            }
            "getPosition" -> result.success(player?.currentPosition ?: 0L)
            "getDuration" -> result.success(player?.duration ?: 0L)
            "isPlaying" -> result.success(player?.isPlaying ?: false)
            "release" -> { release(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun create(result: MethodChannel.Result) {
        val b = binding ?: return result.error("NO_BINDING", "Plugin not attached", null)
        textureEntry = b.textureRegistry.createSurfaceTexture()
        val st = textureEntry!!.surfaceTexture()
        surface = Surface(st)

        player = IjkMediaPlayer().apply {
            setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", 1)
            setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "opensles", 1)
            setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "protocol_whitelist", "concat,file,http,https,tcp,tls,crypto")
            setOption(IjkMediaPlayer.OPT_CATEGORY_CODEC, "skip_loop_filter", 48)
            setSurface(this@FntvIjkplayerPlugin.surface)
        }

        result.success(mapOf("textureId" to textureEntry!!.id()))
    }

    private fun setDataSource(url: String, headers: Map<String, String>, seekMs: Int, result: MethodChannel.Result) {
        try {
            val p = player ?: return result.error("NO_PLAYER", "Player not created", null)

            val hdr = StringBuilder()
            for ((k, v) in headers) hdr.append("$k: $v\r\n")
            if (hdr.isNotEmpty()) {
                p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "headers", hdr.toString())
            }

            p.dataSource = url
            p.prepareAsync()

            p.setOnPreparedListener {
                if (seekMs > 0) p.seekTo(seekMs.toLong())
                p.start()
                startPolling()
                result.success(null)
            }
            p.setOnErrorListener { _, what, extra ->
                try { result.error("IJK_ERROR", "what=$what extra=$extra", null) } catch (_: IllegalStateException) {}
                true
            }
            p.setOnCompletionListener {
                handler.post { channel.invokeMethod("onCompleted", null) }
            }
        } catch (e: Exception) {
            result.error("SET_DATA_ERROR", e.message, null)
        }
    }

    private fun startPolling() {
        stopPolling()
        pollRunnable = object : Runnable {
            override fun run() {
                player?.let {
                    try {
                        val pos = it.currentPosition
                        val dur = it.duration
                        handler.post {
                            channel.invokeMethod("onPosition", mapOf("position" to pos, "duration" to dur))
                        }
                    } catch (_: Exception) {}
                }
                handler.postDelayed(this, 500)
            }
        }
        handler.post(pollRunnable!!)
    }

    private fun stopPolling() {
        pollRunnable?.let { handler.removeCallbacks(it) }
        pollRunnable = null
    }

    private fun release() {
        stopPolling()
        try { player?.release() } catch (_: Exception) {}
        player = null
        surface?.release()
        surface = null
        textureEntry?.release()
        textureEntry = null
    }
}
