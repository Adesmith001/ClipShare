package com.adesmith001.clipshare

import android.app.DownloadManager
import android.content.ContentValues
import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Environment
import android.os.Build
import android.provider.MediaStore
import java.io.IOException
import java.util.UUID

internal class AndroidDownloads(private val context: Context) {
    companion object {
        private val changeLock = Any()

        fun directVideo(url: Uri): Boolean =
            url.scheme.equals("https", ignoreCase = true) &&
                !url.host.isNullOrEmpty() && url.userInfo == null &&
                url.path?.endsWith(".mp4", ignoreCase = true) == true

        private fun downloadKey(url: Uri): String = url.normalizeScheme().buildUpon()
            .encodedAuthority(url.encodedAuthority?.lowercase())
            .fragment(null)
            .build()
            .toString()
    }

    private val manager = context.getSystemService(DownloadManager::class.java)
    private val history = context.getSharedPreferences("downloads", Context.MODE_PRIVATE)

    fun enqueue(url: Uri): Boolean = synchronized(changeLock) {
        queue(url)
    }

    fun enqueueResolved(url: Uri, source: Uri, replacing: Long?): Boolean =
        synchronized(changeLock) {
            if (replacing != null) {
                val previous = entries(setOf(replacing)).singleOrNull()
                if (previous?.get("state") !in listOf("failed", "cancelled")) {
                    return@synchronized false
                }
            }
            queue(url, replacing, source)
        }

    private fun queue(url: Uri, replacing: Long? = null, original: Uri = url): Boolean {
        require(directVideo(url))
        val source = original.toString()
        val key = downloadKey(original)
        val matching = history.all.mapNotNull { (id, value) ->
            if (value is String && downloadKey(Uri.parse(value)) == key) id.toLongOrNull()
            else null
        }.toSet()
        if (entries(matching).any { it["state"] == "downloading" || it["state"] == "saved" }) {
            return false
        }

        val request = DownloadManager.Request(url.normalizeScheme())
            .setTitle("ClipShare video")
            .setDestinationInExternalFilesDir(
                context, Environment.DIRECTORY_MOVIES, "${UUID.randomUUID()}.mp4"
            )
        val id = manager.enqueue(request)
        val edit = history.edit().putString(id.toString(), source)
        if (replacing != null) edit.remove(replacing.toString()).remove("cancelled:$replacing")
        if (!edit.commit()) {
            manager.remove(id)
            throw IOException("Could not record the download.")
        }
        if (replacing != null) manager.remove(replacing)
        return true
    }

    fun cancel(id: Long): Boolean = synchronized(changeLock) {
        if (entries(setOf(id)).singleOrNull()?.get("state") != "downloading") {
            return@synchronized false
        }
        if (manager.remove(id) == 0) return@synchronized false
        if (!history.edit().putBoolean("cancelled:$id", true).commit()) {
            throw IOException("Could not update the download.")
        }
        true
    }

    fun retry(id: Long): Boolean = synchronized(changeLock) {
        val entry = entries(setOf(id)).singleOrNull() ?: return@synchronized false
        if (entry["state"] !in listOf("failed", "cancelled")) return@synchronized false
        queue(Uri.parse(entry.getValue("url") as String), replacing = id)
    }

    fun tracks(id: Long): Boolean = history.contains(id.toString())

    fun entries(only: Set<Long>? = null): List<Map<String, Any>> {
        val sources = history.all.mapNotNull { (key, value) ->
            val id = key.toLongOrNull()
            if (id == null || value !is String || (only != null && id !in only)) null else id to value
        }.toMap()
        if (sources.isEmpty()) return emptyList()

        val states = mutableMapOf<Long, String>()
        val progress = mutableMapOf<Long, Double>()
        manager.query(DownloadManager.Query().setFilterById(*sources.keys.toLongArray())).use { row ->
            val idColumn = row.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)
            val statusColumn = row.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            val receivedColumn = row.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            val totalColumn = row.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            while (row.moveToNext()) {
                val id = row.getLong(idColumn)
                states[id] = when (row.getInt(statusColumn)) {
                    DownloadManager.STATUS_SUCCESSFUL -> if (isVideo(id)) "saved" else "failed"
                    DownloadManager.STATUS_FAILED -> "failed"
                    else -> "downloading"
                }
                val total = row.getLong(totalColumn)
                if (states[id] == "downloading" && total > 0) {
                    progress[id] = (row.getLong(receivedColumn).toDouble() / total).coerceIn(0.0, 1.0)
                }
            }
        }
        return sources.entries.sortedByDescending { it.key }.map { (id, url) ->
            val state = states[id] ?: if (history.getBoolean("cancelled:$id", false)) "cancelled" else "failed"
            buildMap {
                put("id", id.toString())
                put("url", url)
                put("state", state)
                put("canCancel", state == "downloading")
                put("canRetry", state == "cancelled" || state == "failed")
                put("canExport", state == "saved" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                progress[id]?.let { put("progress", it) }
            }
        }
    }

    fun export(id: Long): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || videoUri(id) == null) return false
        val resolver = context.contentResolver
        val fields = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, "ClipShare-$id.mp4")
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/ClipShare")
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val destination = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, fields)
            ?: throw IOException("Could not create a Gallery entry.")
        try {
            android.os.ParcelFileDescriptor.AutoCloseInputStream(manager.openDownloadedFile(id)).use { input ->
                val output = resolver.openOutputStream(destination)
                    ?: throw IOException("Could not open the Gallery entry.")
                output.use { input.copyTo(it) }
            }
            fields.clear()
            fields.put(MediaStore.Video.Media.IS_PENDING, 0)
            if (resolver.update(destination, fields, null, null) != 1) {
                throw IOException("Could not publish the Gallery entry.")
            }
            return true
        } catch (error: Exception) {
            resolver.delete(destination, null, null)
            throw error
        }
    }

    fun videoUri(id: Long): Uri? =
        if (tracks(id) && isVideo(id)) manager.getUriForDownloadedFile(id) else null

    private fun isVideo(id: Long): Boolean {
        return try {
            manager.openDownloadedFile(id).use { file ->
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(file.fileDescriptor)
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
                } finally {
                    retriever.release()
                }
            }
        } catch (error: Exception) {
            false
        }
    }
}
