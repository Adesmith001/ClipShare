package com.adesmith001.clipshare

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.MediaController
import android.widget.Toast
import android.widget.VideoView

class VideoActivity : Activity() {
    private lateinit var player: VideoView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent.data
        if (uri == null) {
            finish()
            return
        }

        player = VideoView(this)
        val frame = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            addView(
                player, FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER
                )
            )
        }
        setContentView(frame)
        player.setMediaController(MediaController(this))
        player.setOnErrorListener { _, _, _ ->
            Toast.makeText(this, "This video couldn’t be played.", Toast.LENGTH_SHORT).show()
            finish()
            true
        }
        player.setVideoURI(uri)
        player.start()
    }

    override fun onPause() {
        if (::player.isInitialized) player.pause()
        super.onPause()
    }
}
