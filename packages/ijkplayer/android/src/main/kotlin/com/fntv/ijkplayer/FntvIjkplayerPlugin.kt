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
import tv.danmaku.ijk.media.player.IMediaPlayer

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
            
            Log.i(TAG, "Creating texture...")
            textureEntry = b.textureRegistry.createSurfaceTexture()
            val st = textureEntry!!.surfaceTexture()
            surface = Surface(st)
            Log.i(TAG, "Texture created, id=${textureEntry!!.id()}")

            Log.i(TAG, "Creating IjkMediaPlayer...")
            // Use default IjkLibLoader (System.loadLibrary)
            val libLoader = object : IjkMediaPlayer.IjkLibLoader {
                override fun loadLibrary(name: String) {
                    System.loadLibrary(name)
                }
            }
            player = IjkMediaPlayer(libLoader)
            player!!.apply {
                setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", 1)
                setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "opensles", 0)
                setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "protocol_whitelist", "concat,file,http,https,tcp,tls,crypto")
                setOption(IjkMediaPlayer.OPT_CATEGORY_CODEC, "skip_loop_filter", 48)
                setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 0)
                setSurface(this@FntvIjkplayerPlugin.surface)
            }
            
            Log.i(TAG, "Player created successfully, textureId=${textureEntry!!.id()}")
            result.success(mapOf("textureId" to textureEntry!!.id()))
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Native library load failed!", e)
            result.error("NATIVE_LIB_ERROR", "Failed to load ijkplayer native libs: ${e.message}", null)
        } catch (e: Exception) {
            Log.e(TAG, "Create error", e)
            result.error("CREATE_ERROR", e.message, null)
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

            p.setDataSource(url)
            Log.i(TAG, "prepareAsync...")
            p.prepareAsync()

            p.setOnPreparedListener(IMediaPlayer.OnPreparedListener { mp ->
                Log.i(TAG, "Prepared! seekMs=$seekMs")
                if (seekMs > 0) mp.seekTo(seekMs.toLong())
                mp.start()
                startPolling()
                try { result.success(null) } catch (_: Exception) {}
            })
            p.setOnErrorListener(IMediaPlayer.OnErrorListener { _, what, extra ->
                Log.e(TAG, "Player error: what=$what extra=$extra")
                try { result.error("IJK_ERROR", "what=$what extra=$extra", null) } catch (_: Exception) {}
                true
            })
            p.setOnCompletionListener(IMediaPlayer.OnCompletionListener {
                Log.i(TAG, "Playback completed")
                handler.post { channel.invokeMethod("onCompleted", null) }
            })
            p.setOnInfoListener(IMediaPlayer.OnInfoListener { _, what, extra ->
                Log.d(TAG, "Info: what=$what extra=$extra")
                false
            })
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
}
