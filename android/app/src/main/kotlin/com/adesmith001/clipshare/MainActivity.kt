package com.adesmith001.clipshare

import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class MainActivity : FlutterActivity() {
    private val downloads by lazy { AndroidDownloads(applicationContext) }
    private val appUpdates by lazy { AppUpdateManagerFactory.create(this) }
    private var updateChannel: MethodChannel? = null
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
        MethodChannel(messenger, "clipshare/preferences").setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("clipshare_settings", Context.MODE_PRIVATE)
            val allowed = mapOf(
                "theme" to setOf("system", "light", "dark"),
                "filter" to setOf("All", "Photos", "Videos"),
                "sort" to setOf("newest", "oldest")
            )
            when (call.method) {
                "read" -> result.success((allowed.keys + setOf("tutorialSeen", "seenReleaseBuild"))
                    .associateWith { prefs.getString(it, null) }.filterValues { it != null } +
                    ("installedBuild" to BuildConfig.VERSION_CODE.toString()))
                "markTutorialSeen" -> result.success(prefs.edit().putString("tutorialSeen", "true").commit())
                "markReleaseSeen" -> {
                    val build = call.arguments as? String
                    result.success(build == BuildConfig.VERSION_CODE.toString() &&
                        prefs.edit().putString("seenReleaseBuild", build).commit())
                }
                "write" -> {
                    val values = call.arguments as? Map<*, *>
                    if (values == null || values.keys != allowed.keys ||
                        allowed.any { (key, options) -> values[key] !in options }) {
                        result.error("invalid_argument", null, null)
                    } else {
                        val edit = prefs.edit()
                        allowed.keys.forEach { edit.putString(it, values[it] as String) }
                        result.success(edit.commit())
                    }
                }
                else -> result.notImplemented()
            }
        }
        updateChannel = MethodChannel(messenger, "clipshare/updates").also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                when (call.method) {
                    "check", "start" -> handlePlayUpdate(call.method == "start", result)
                    else -> result.notImplemented()
                }
            }
        }
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
                    "folders", "info", "reconcile" -> {
                        try {
                            result.success(when (call.method) {
                                "folders" -> downloads.folders()
                                "info" -> downloads.info()
                                else -> downloads.reconcile()
                            })
                        } catch (error: Exception) {
                            result.error("shared_links_unavailable", null, null)
                        }
                    }
                    "createFolder", "deleteFolder", "renameFolder", "move" -> {
                        try {
                            val completed = when (call.method) {
                                "createFolder" -> downloads.createFolder(call.arguments as? String
                                    ?: throw IllegalArgumentException())
                                "deleteFolder" -> downloads.deleteFolder(call.arguments as? String
                                    ?: throw IllegalArgumentException())
                                "renameFolder" -> downloads.renameFolder(
                                    call.argument<String>("from") ?: throw IllegalArgumentException(),
                                    call.argument<String>("to") ?: throw IllegalArgumentException()
                                )
                                else -> {
                                    val ids = call.argument<List<Any>>("ids")?.map {
                                        (it as? String)?.toLongOrNull() ?: throw IllegalArgumentException()
                                    } ?: throw IllegalArgumentException()
                                    downloads.move(ids, call.argument<String>("folder")
                                        ?: throw IllegalArgumentException())
                                }
                            }
                            result.success(completed)
                        } catch (error: IllegalArgumentException) {
                            result.error("invalid_argument", null, null)
                        } catch (error: Exception) {
                            result.error("download_action_failed", null, null)
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
                    "videoUri" -> {
                        val id = (call.arguments as? String)?.toLongOrNull()
                        result.success(id?.let(downloads::videoUri)?.toString())
                    }
                    "addResolved" -> {
                        val media = call.argument<String>("media")?.let(Uri::parse)
                        val source = call.argument<String>("source")?.let(Uri::parse)
                        val replacingValue = call.argument<String>("replacing")
                        val replacing = replacingValue?.toLongOrNull()
                        if (media == null || source == null || (replacingValue != null && replacing == null)) {
                            result.error("invalid_argument", null, null)
                        } else {
                            try {
                                result.success(downloads.enqueueResolved(
                                    media, source, replacing, call.argument<String>("title"),
                                    call.argument<String>("slot")?.toIntOrNull() ?: 0,
                                    call.argument<String>("position"),
                                    call.argument<String>("sharedSource")?.let(Uri::parse),
                                    call.argument<String>("folder")
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
                    "add", "cancel", "retry", "export", "delete" -> {
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
                                    "delete" -> downloads.delete(id)
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
        updateChannel?.setMethodCallHandler(null)
        updateChannel = null
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handlePlayUpdate(start: Boolean, result: MethodChannel.Result) {
        appUpdates.appUpdateInfo.addOnSuccessListener { info ->
            val availability = info.updateAvailability()
            val canUpdate = availability == UpdateAvailability.UPDATE_AVAILABLE ||
                availability == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
            if (!start) {
                result.success(if (canUpdate) "Google Play" else null)
            } else if (!canUpdate || isFinishing || isDestroyed) {
                result.success(false)
            } else if (!info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)) {
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName")))
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.success(false)
                }
            } else {
                appUpdates.startUpdateFlow(
                    info, this, AppUpdateOptions.defaultOptions(AppUpdateType.IMMEDIATE)
                ).addOnCompleteListener { update ->
                    result.success(update.isSuccessful && update.result == RESULT_OK)
                }
            }
        }.addOnFailureListener {
            result.error("play_update_check_failed", null, null)
        }
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
