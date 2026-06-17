package com.fntv.fnos_tv_all

import android.content.Context
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import java.util.concurrent.ConcurrentHashMap

@UnstableApi
object ExoPlayerManager {
    private val players = ConcurrentHashMap<Int, ExoPlayer>()

    fun create(context: Context, playerId: Int) {
        dispose(playerId)
        val appContext = context.applicationContext
        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(30_000)
            .setReadTimeoutMs(30_000)
        val dataSourceFactory = DefaultDataSource.Factory(appContext, httpFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
        val player = ExoPlayer.Builder(appContext)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
        players[playerId] = player
    }

    fun get(playerId: Int): ExoPlayer? = players[playerId]

    fun setSource(
        context: Context,
        playerId: Int,
        url: String,
        headers: Map<String, String>,
        startMs: Long,
    ) {
        val player = players[playerId] ?: return
        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(30_000)
            .setReadTimeoutMs(30_000)
            .setDefaultRequestProperties(headers)
        val dataSourceFactory = DefaultDataSource.Factory(context.applicationContext, httpFactory)
        val mediaSource = DefaultMediaSourceFactory(dataSourceFactory)
            .createMediaSource(MediaItem.fromUri(Uri.parse(url)))
        player.setMediaSource(mediaSource)
        player.prepare()
        if (startMs > 0) player.seekTo(startMs)
    }

    fun play(playerId: Int) { players[playerId]?.play() }
    fun pause(playerId: Int) { players[playerId]?.pause() }

    fun seek(playerId: Int, positionMs: Long) {
        players[playerId]?.seekTo(positionMs.coerceAtLeast(0))
    }

    fun setSpeed(playerId: Int, speed: Float) {
        players[playerId]?.setPlaybackSpeed(speed.coerceIn(0.25f, 4f))
    }

    fun setSubtitleTrack(playerId: Int, listIndex: Int) {
        val player = players[playerId] ?: return
        val textGroups = player.currentTracks.groups.filter { it.type == C.TRACK_TYPE_TEXT }
        if (listIndex < 0) {
            player.trackSelectionParameters = player.trackSelectionParameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
            return
        }
        if (listIndex >= textGroups.size) return
        val group = textGroups[listIndex]
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, 0))
            .build()
    }

    fun setAudioTrack(playerId: Int, listIndex: Int) {
        val player = players[playerId] ?: return
        val audioGroups = player.currentTracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
        if (listIndex < 0 || listIndex >= audioGroups.size) return
        val group = audioGroups[listIndex]
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, 0))
            .build()
    }

    fun getState(playerId: Int): Map<String, Any?> {
        val p = players[playerId] ?: return emptyMap()
        val textTracks = p.currentTracks.groups
            .filter { it.type == C.TRACK_TYPE_TEXT }
            .mapIndexed { i, g -> mapOf("index" to i, "selected" to g.isSelected) }
        return mapOf(
            "positionMs" to p.currentPosition.coerceAtLeast(0),
            "durationMs" to p.duration.coerceAtLeast(0),
            "isPlaying" to p.isPlaying,
            "isBuffering" to p.playbackState == androidx.media3.common.Player.STATE_BUFFERING,
            "videoWidth" to p.videoSize.width,
            "videoHeight" to p.videoSize.height,
            "bitrateEstimate" to 0,
            "textTracks" to textTracks,
        )
    }

    fun dispose(playerId: Int) {
        players.remove(playerId)?.release()
    }
}
