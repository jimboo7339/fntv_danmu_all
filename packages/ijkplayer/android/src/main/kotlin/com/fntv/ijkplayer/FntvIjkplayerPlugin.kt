package com.fntv.ijkplayer

import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import tv.danmaku.ijk.media.player.IjkMediaPlayer

private const val TAG = "FntvIjk"

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
        Log.i(TAG, "Plugin attached")
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
            Log.e(TAG, "Method call error: ${call.method}", e)
            result.error("IJK_ERROR", "${call.method}: ${e.message}", null)
        }
    }

    private fun create(result: MethodChannel.Result) {
        try {
            val b = binding ?: return result.error("NO_BINDING", "Plugin not attached", null)
            
            // Create texture
            Log.i(TAG, "Step 1: Creating texture...")
            textureEntry = b.textureRegistry.createSurfaceTexture()
            val st = textureEntry!!.surfaceTexture()
            surface = Surface(st)
            val texId = textureEntry!!.id()
            Log.i(TAG, "Step 1 done: textureId=$texId")

            // Create player — on background thread to avoid ANR
            Log.i(TAG, "Step 2: Creating IjkMediaPlayer on background thread...")
            Thread {
                try {
                    Log.i(TAG, "Step 2a: Instantiating IjkMediaPlayer...")
                    val p = IjkMediaPlayer(b.applicationContext)
                    Log.i(TAG, "Step 2b: IjkMediaPlayer created, applying options...")
                    p.apply {
                        setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", 1)
                        setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "opensles", 0)
                        setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "protocol_whitelist", "concat,file,http,https,tcp,tls,crypto")
                        setOption(IjkMediaPlayer.OPT_CATEGORY_CODEC, "skip_loop_filter", 48)
                        setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 0)
                        setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "overlay-format", IjkMediaPlayer.SDL_FCC_RV32)
                        Log.i(TAG, "Step 2c: Options set, attaching surface...")
                        setSurface(this@FntvIjkplayerPlugin.surface)
                        Log.i(TAG, "Step 2d: Surface attached")
                    }
                    player = p
                    Log.i(TAG, "Step 2 done: Player ready")
                    handler.post {
                        result.success(mapOf("textureId" to texId))
                    }
                } catch (e: UnsatisfiedLinkError) {
                    Log.e(TAG, "Step 2 FAIL: Native lib error", e)
                    handler.post {
                        result.error("NATIVE_LIB_ERROR", "Native libs: ${e.message}", null)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Step 2 FAIL: Create error", e)
                    handler.post {
                        result.error("CREATE_ERROR", e.message, null)
                    }
                }
            }.start()
        } catch (e: Exception) {
            Log.e(TAG, "Step 1 FAIL: Texture error", e)
            result.error("TEXTURE_ERROR", e.message, null)
        }
    }

    private fun setDataSource(url: String, headers: Map<String, String>, seekMs: Int, result: MethodChannel.Result) {
        try {
            val p = player ?: return result.error("NO_PLAYER", "Player not created", null)
            Log.i(TAG, "setDataSource: url=${url.take(80)}... seekMs=$seekMs")

            // Set HTTP headers
            val hdr = StringBuilder()
            for ((k, v) in headers) hdr.append("$k: $v\r\n")
            if (hdr.isNotEmpty()) {
                p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "headers", hdr.toString())
            }

            p.dataSource = url
            Log.i(TAG, "prepareAsync...")
            p.prepareAsync()

            p.setOnPreparedListener {
                Log.i(TAG, "Prepared! seekMs=$seekMs")
                if (seekMs > 0) p.seekTo(seekMs.toLong())
                p.start()
                startPolling()
                try { result.success(null) } catch (_: Exception) {}
            }
            p.setOnErrorListener { _, what, extra ->
                Log.e(TAG, "Player error: what=$what extra=$extra")
                try { result.error("IJK_ERROR", "what=$what extra=$extra", null) } catch (_: Exception) {}
                true
            }
            p.setOnCompletionListener {
                Log.i(TAG, "Playback completed")
                handler.post { channel.invokeMethod("onCompleted", null) }
            }
            p.setOnInfoListener { _, what, extra ->
                if (what == IMEDIA_INFO_VIDEO_RENDERING_START) {
                    Log.i(TAG, "Video rendering started!")
                }
                Log.d(TAG, "Info: what=$what extra=$extra")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "setDataSource error", e)
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
        Log.i(TAG, "Released")
    }

    companion object {
        private const val IMEDIA_INFO_VIDEO_RENDERING_START = 3
    }
}
