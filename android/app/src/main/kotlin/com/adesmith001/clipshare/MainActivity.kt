package com.adesmith001.clipshare

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class MainActivity : FlutterActivity() {
    private val downloads by lazy { AndroidDownloads(applicationContext) }
    private var channel: MethodChannel? = null
    private val completionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
            if (intent.action == DownloadManager.ACTION_DOWNLOAD_COMPLETE && downloads.tracks(id)) {
                channel?.invokeMethod("changed", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        channel = MethodChannel(
            messenger, "clipshare/shared_links", StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue()
        ).also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                when (call.method) {
                    "list" -> {
                        try {
                            result.success(downloads.entries())
                        } catch (error: Exception) {
                            result.error("shared_links_unavailable", null, null)
                        }
                    }
                    "play" -> {
                        val id = (call.arguments as? String)?.toLongOrNull()
                        val uri = id?.let(downloads::videoUri)
                        runOnUiThread {
                            if (uri == null || isFinishing || isDestroyed) {
                                result.error("video_unavailable", null, null)
                            } else {
                                startActivity(Intent(this, VideoActivity::class.java).setData(uri))
                                result.success(null)
                            }
                        }
                    }
                    "addResolved" -> {
                        val media = call.argument<String>("media")?.let(Uri::parse)
                        val source = call.argument<String>("source")?.let(Uri::parse)
                        val replacing = call.argument<String>("replacing")?.toLongOrNull()
                        if (media == null || source == null) {
                            result.error("invalid_argument", null, null)
                        } else {
                            try {
                                result.success(downloads.enqueueResolved(
                                    media, source, replacing, call.argument<String>("title"),
                                    call.argument<String>("slot")?.toIntOrNull() ?: 0,
                                    call.argument<String>("position")
                                ))
                            } catch (error: Exception) {
                                result.error("download_action_failed", null, null)
                            }
                        }
                    }
                    "thumbnail", "preview" -> {
                        val id = (call.arguments as? String)?.toLongOrNull()
                        val size = if (call.method == "preview") 1600 else 400
                        result.success(id?.let { downloads.thumbnail(it, size) })
                    }
                    "add", "cancel", "retry", "export" -> {
                        val argument = call.arguments as? String
                        if (argument == null) {
                            result.error("invalid_argument", null, null)
                            return@setMethodCallHandler
                        }
                        try {
                            if (call.method == "add") {
                                result.success(downloads.enqueue(Uri.parse(argument)))
                            } else {
                                val id = argument.toLong()
                                val completed = when (call.method) {
                                    "cancel" -> downloads.cancel(id)
                                    "retry" -> downloads.retry(id)
                                    else -> downloads.export(id)
                                }
                                result.success(completed)
                            }
                        } catch (error: Exception) {
                            result.error("download_action_failed", null, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(completionReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(completionReceiver, filter)
        }
        channel?.invokeMethod("changed", null)
    }

    override fun onStop() {
        unregisterReceiver(completionReceiver)
        super.onStop()
    }
}
