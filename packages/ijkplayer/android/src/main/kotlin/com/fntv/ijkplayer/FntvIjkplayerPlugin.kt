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
        try {
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
        } catch (e: Exception) {
            android.util.Log.e("FntvIjk", "Method call error: ${call.method}", e)
            result.error("IJK_ERROR", "${call.method}: ${e.message}", e.stackTraceToString())
        }
    }

    private fun create(result: MethodChannel.Result) {
        try {
            val b = binding ?: return result.error("NO_BINDING", "Plugin not attached", null)
            textureEntry = b.textureRegistry.createSurfaceTexture()
            val st = textureEntry!!.surfaceTexture()
            surface = Surface(st)

            // Load native library first
            try {
                IjkMediaPlayer.loadLibrariesOnce(null)
            } catch (e: UnsatisfiedLinkError) {
                android.util.Log.e("FntvIjk", "Native library load failed", e)
                release()
                return result.error("NATIVE_LIB_ERROR", "Failed to load ijkplayer native libraries: ${e.message}", null)
            }

            player = IjkMediaPlayer().apply {
                // Conservative options to avoid crashes
                setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", 1)
                setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "opensles", 0) // disable opensles to avoid audio issues
                setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "protocol_whitelist", "concat,file,http,https,tcp,tls,crypto")
                setOption(IjkMediaPlayer.OPT_CATEGORY_CODEC, "skip_loop_filter", 48)
                setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 0) // don't auto-start
                setSurface(this@FntvIjkplayerPlugin.surface)
            }

            android.util.Log.i("FntvIjk", "Player created, textureId=${textureEntry!!.id()}")
            result.success(mapOf("textureId" to textureEntry!!.id()))
        } catch (e: Exception) {
            android.util.Log.e("FntvIjk", "Create error", e)
            result.error("CREATE_ERROR", e.message, e.stackTraceToString())
        }
    }

    private fun setDataSource(url: String, headers: Map<String, String>, seekMs: Int, result: MethodChannel.Result) {
        try {
            val p = player ?: return result.error("NO_PLAYER", "Player not created", null)

            // Set HTTP headers
            val hdr = StringBuilder()
            for ((k, v) in headers) hdr.append("$k: $v\r\n")
            if (hdr.isNotEmpty()) {
                p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "headers", hdr.toString())
            }

            p.dataSource = url
            p.prepareAsync()

            p.setOnPreparedListener {
                android.util.Log.i("FntvIjk", "Prepared, seekMs=$seekMs")
                if (seekMs > 0) p.seekTo(seekMs.toLong())
                p.start()
                startPolling()
                try { result.success(null) } catch (_: IllegalStateException) {}
            }
            p.setOnErrorListener { _, what, extra ->
                android.util.Log.e("FntvIjk", "Player error: what=$what extra=$extra")
                try { result.error("IJK_ERROR", "what=$what extra=$extra", null) } catch (_: IllegalStateException) {}
                true
            }
            p.setOnCompletionListener {
                handler.post { channel.invokeMethod("onCompleted", null) }
            }
        } catch (e: Exception) {
            android.util.Log.e("FntvIjk", "setDataSource error", e)
            result.error("SET_DATA_ERROR", e.message, e.stackTraceToString())
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
