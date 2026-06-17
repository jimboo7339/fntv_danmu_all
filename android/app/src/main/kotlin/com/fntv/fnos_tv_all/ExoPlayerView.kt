package com.fntv.fnos_tv_all

import android.content.Context
import android.view.View
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.platform.PlatformView

@UnstableApi
class ExoPlayerView(
    context: Context,
    private val playerId: Int,
    messenger: BinaryMessenger,
) : PlatformView {
    private val playerView: PlayerView = PlayerView(context).apply {
        useController = false
        subtitleView?.visibility = View.VISIBLE
    }

    init {
        ExoPlayerManager.get(playerId)?.let { playerView.player = it }
    }

    override fun getView(): View = playerView

    override fun dispose() {
        playerView.player = null
    }
}
