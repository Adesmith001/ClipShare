package com.adesmith001.clipshare

import android.app.DownloadManager
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Environment
import android.os.Build
import android.provider.MediaStore
import java.io.IOException
import java.io.ByteArrayOutputStream
import java.util.UUID

internal class AndroidDownloads(private val context: Context) {
    companion object {
        private val changeLock = Any()

        fun directVideo(url: Uri): Boolean =
            url.scheme.equals("https", ignoreCase = true) &&
                !url.host.isNullOrEmpty() && url.userInfo == null &&
                url.path?.endsWith(".mp4", ignoreCase = true) == true

        fun imageExtension(url: Uri): String? {
            if (!url.scheme.equals("https", ignoreCase = true) ||
                url.host.isNullOrEmpty() || url.userInfo != null) return null
            return when (url.path?.substringAfterLast('.')?.lowercase()) {
                "jpg", "jpeg" -> "jpg"
                "png" -> "png"
                else -> null
            }
        }

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

    fun enqueueResolved(url: Uri, source: Uri, replacing: Long?, title: String?): Boolean =
        synchronized(changeLock) {
            if (replacing != null) {
                val previous = entries(setOf(replacing)).singleOrNull()
                if (previous?.get("state") !in listOf("failed", "cancelled")) {
                    return@synchronized false
                }
            }
            queue(url, replacing, source, title)
        }

    private fun queue(
        url: Uri, replacing: Long? = null, original: Uri = url, title: String? = null
    ): Boolean {
        val image = imageExtension(url)
        require(
            image != null || directVideo(url) ||
                (original != url && url.scheme == "https" && url.userInfo == null &&
                    url.host?.endsWith(".googlevideo.com") == true && url.path == "/videoplayback" &&
                    url.getQueryParameter("mime") == "video/mp4")
        )
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
            .setTitle(title ?: "ClipShare download")
            .setDestinationInExternalFilesDir(
                context, directory(image), "${UUID.randomUUID()}.${image ?: "mp4"}"
            )
        val id = manager.enqueue(request)
        val edit = history.edit().putString(id.toString(), source)
        if (image != null) edit.putString("image:$id", image)
        if (title != null) edit.putString("title:$id", title)
        if (replacing != null) {
            edit.remove(replacing.toString()).remove("cancelled:$replacing")
                .remove("image:$replacing").remove("title:$replacing")
        }
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
                    DownloadManager.STATUS_SUCCESSFUL -> if (validMedia(id)) "saved" else "failed"
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
                put("isImage", imageType(id) != null)
                history.getString("title:$id", null)?.let { put("title", it) }
                progress[id]?.let { put("progress", it) }
            }
        }
    }

    fun export(id: Long): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !tracks(id) || !validMedia(id)) return false
        val image = imageType(id)
        val collection = if (image == null) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val resolver = context.contentResolver
        val fields = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "ClipShare-$id.${image ?: "mp4"}")
            put(MediaStore.MediaColumns.MIME_TYPE, if (image == null) "video/mp4" else imageMime(image))
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${directory(image)}/ClipShare")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val destination = resolver.insert(collection, fields)
            ?: throw IOException("Could not create a Gallery entry.")
        try {
            android.os.ParcelFileDescriptor.AutoCloseInputStream(manager.openDownloadedFile(id)).use { input ->
                val output = resolver.openOutputStream(destination)
                    ?: throw IOException("Could not open the Gallery entry.")
                output.use { input.copyTo(it) }
            }
            fields.clear()
            fields.put(MediaStore.MediaColumns.IS_PENDING, 0)
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
        if (tracks(id) && imageType(id) == null && validMedia(id)) manager.getUriForDownloadedFile(id) else null

    private fun imageType(id: Long): String? = history.getString("image:$id", null)

    private fun directory(image: String?): String =
        if (image == null) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES

    private fun imageMime(image: String): String =
        if (image == "png") "image/png" else "image/jpeg"

    private fun imageBitmap(id: Long, image: String, size: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        manager.openDownloadedFile(id).use { BitmapFactory.decodeFileDescriptor(it.fileDescriptor, null, bounds) }
        if (bounds.outMimeType != imageMime(image) || bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply {
            inSampleSize = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / inSampleSize > size * 2) inSampleSize *= 2
        }
        return manager.openDownloadedFile(id).use {
            BitmapFactory.decodeFileDescriptor(it.fileDescriptor, null, options)
        }
    }

    fun thumbnail(id: Long, size: Int): ByteArray? {
        if (!tracks(id)) return null
        return try {
            val image = imageType(id)
            val bitmap = if (image != null) imageBitmap(id, image, size) else {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return null
                manager.openDownloadedFile(id).use { file ->
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(file.fileDescriptor)
                        retriever.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, size, size)
                    } finally {
                        retriever.release()
                    }
                }
            } ?: return null
            try {
                ByteArrayOutputStream().use { stream ->
                    if (bitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream)) stream.toByteArray()
                    else null
                }
            } finally {
                bitmap.recycle()
            }
        } catch (error: Exception) {
            null
        }
    }

    private fun validMedia(id: Long): Boolean {
        return try {
            val image = imageType(id)
            if (image != null) {
                val bitmap = imageBitmap(id, image, 32) ?: return false
                bitmap.recycle()
                return true
            }
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
