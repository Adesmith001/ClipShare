package com.adesmith001.clipshare

import android.app.DownloadManager
import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Environment
import java.io.IOException
import java.util.UUID

internal class AndroidDownloads(private val context: Context) {
    private val manager = context.getSystemService(DownloadManager::class.java)
    private val history = context.getSharedPreferences("downloads", Context.MODE_PRIVATE)

    fun enqueue(url: Uri) {
        val request = DownloadManager.Request(url)
            .setTitle("ClipShare video")
            .setDestinationInExternalFilesDir(
                context, Environment.DIRECTORY_MOVIES, "${UUID.randomUUID()}.mp4"
            )
        val id = manager.enqueue(request)
        if (!history.edit().putString(id.toString(), url.toString()).commit()) {
            manager.remove(id)
            throw IOException("Could not record the download.")
        }
    }

    fun tracks(id: Long): Boolean = history.contains(id.toString())

    fun entries(): List<Map<String, String>> {
        val sources = history.all.mapNotNull { (key, value) ->
            val id = key.toLongOrNull()
            if (id == null || value !is String) null else id to value
        }.toMap()
        if (sources.isEmpty()) return emptyList()

        val states = mutableMapOf<Long, String>()
        manager.query(DownloadManager.Query().setFilterById(*sources.keys.toLongArray())).use { row ->
            val idColumn = row.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)
            val statusColumn = row.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            while (row.moveToNext()) {
                val id = row.getLong(idColumn)
                states[id] = when (row.getInt(statusColumn)) {
                    DownloadManager.STATUS_SUCCESSFUL -> if (isVideo(id)) "saved" else "failed"
                    DownloadManager.STATUS_FAILED -> "failed"
                    else -> "downloading"
                }
            }
        }
        return sources.entries.sortedByDescending { it.key }.map { (id, url) ->
            mapOf("id" to id.toString(), "url" to url, "state" to (states[id] ?: "failed"))
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
