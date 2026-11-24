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
import java.io.File
import java.util.concurrent.ConcurrentHashMap

internal class AndroidDownloads(
    private val context: Context,
    // Optional platform seams let device tests exercise queue transactions without networking.
    private val enqueueTransfer: ((DownloadManager.Request) -> Long)? = null,
    private val transferState: ((Long) -> String?)? = null
) {
    companion object {
        private val changeLock = Any()
        private val validated = ConcurrentHashMap<Long, Pair<String, Boolean>>()

        internal fun validateFile(id: Long, file: File?, decode: () -> Boolean): Boolean {
            if (file?.isFile != true) { validated.remove(id); return false }
            val fingerprint = "${file.path}:${file.length()}:${file.lastModified()}"
            val cached = validated[id]
            if (cached?.first == fingerprint) return cached.second
            return decode().also { validated[id] = fingerprint to it }
        }

        fun socialLink(url: Uri): Boolean {
            if (BuildConfig.STORE_BETA) return false
            if (!url.scheme.equals("https", true) || url.host.isNullOrEmpty() || url.userInfo != null) return false
            if (tikTokLink(url)) return true
            val host = url.host!!.lowercase()
            val path = url.path.orEmpty()
            return when {
                host in setOf("x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com") ->
                    Regex("^/(?:i/web|[^/]+)/status/[0-9]+(?:/|$)").containsMatchIn(path)
                host == "pinterest.com" || host.endsWith(".pinterest.com") ->
                    Regex("^/pin/(?:[\\w-]+--)?[0-9]+/?$").matches(path)
                host == "pin.it" -> url.pathSegments.size == 1
                host in setOf("instagram.com", "www.instagram.com", "m.instagram.com") ->
                    Regex("^/(?:p|reels?|tv)/[\\w-]+/?$").matches(path)
                host == "youtu.be" || host in setOf("youtube.com", "www.youtube.com", "m.youtube.com") -> {
                    val parts = url.pathSegments
                    val id = when {
                        host == "youtu.be" && parts.size == 1 -> parts[0]
                        path == "/watch" -> url.getQueryParameter("v")
                        parts.size == 2 && parts[0] in setOf("shorts", "live") -> parts[1]
                        else -> null
                    }
                    id != null && Regex("^[A-Za-z0-9_-]{11}$").matches(id)
                }
                else -> false
            }
        }

        private fun tikTokVideoId(url: Uri): String? {
            if (url.host?.lowercase() !in setOf("tiktok.com", "www.tiktok.com", "m.tiktok.com")) return null
            return (Regex("^/@[\\w.-]+/video/([0-9]+)/?$").matchEntire(url.path.orEmpty())
                ?: Regex("^/v/([0-9]+)\\.html/?$").matchEntire(url.path.orEmpty()))?.groupValues?.get(1)
        }

        private fun tikTokLink(url: Uri): Boolean {
            if (!url.scheme.equals("https", true) || url.userInfo != null) return false
            if (tikTokVideoId(url) != null) return true
            return when (url.host?.lowercase()) {
                "vm.tiktok.com", "vt.tiktok.com" -> Regex("^/[\\w-]+/?$").matches(url.path.orEmpty())
                "tiktok.com", "www.tiktok.com", "m.tiktok.com" -> Regex("^/t/[\\w-]+/?$").matches(url.path.orEmpty())
                else -> false
            }
        }

        internal fun tikTokMedia(url: Uri): Boolean {
            if (url.scheme != "https" || url.userInfo != null) return false
            val host = url.host?.lowercase() ?: return false
            if (host in setOf("tikwm.com", "www.tikwm.com")) return url.path?.startsWith("/video/") == true
            return listOf("tiktokcdn.com", "tiktokcdn-us.com", "tiktokcdn-eu.com", "tiktokv.com")
                .any { host == it || host.endsWith(".$it") } && url.path?.contains("/video/") == true
        }

        fun supportedLink(url: Uri): Boolean = directVideo(url) || imageExtension(url) != null || socialLink(url)

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
                "webp" -> "webp"
                else -> null
            }
        }

        private fun downloadKey(url: Uri): String {
            if (socialLink(url)) {
                val host = url.host!!.lowercase()
                val path = url.path.orEmpty()
                return when {
                    tikTokVideoId(url) != null -> "tiktok:${tikTokVideoId(url)}"
                    tikTokLink(url) -> "$host:${path.trimEnd('/')}"
                    host == "pin.it" -> "pin.it:${url.pathSegments.single()}"
                    host == "pinterest.com" || host.endsWith(".pinterest.com") ->
                        "pinterest:${Regex("(?:[\\w-]+--)?([0-9]+)/?$").find(path)!!.groupValues[1]}"
                    host.contains("instagram.com") -> "instagram:${url.pathSegments.last()}"
                    host.contains("youtube.com") || host == "youtu.be" ->
                        "youtube:${if (path == "/watch") url.getQueryParameter("v") else url.pathSegments.last()}"
                    else -> "x:${Regex("/status/([0-9]+)").find(path)!!.groupValues[1]}"
                }
            }
            return url.normalizeScheme().buildUpon()
                .encodedAuthority(url.encodedAuthority?.lowercase())
                .fragment(null).build().toString()
        }
    }

    private val manager = context.getSystemService(DownloadManager::class.java)
    private val history = context.getSharedPreferences("downloads", Context.MODE_PRIVATE)

    fun enqueue(url: Uri): Boolean = synchronized(changeLock) {
        require(supportedLink(url))
        if (!socialLink(url)) return@synchronized queue(url)
        val key = downloadKey(url)
        if (sourceRows().any { (id, source) -> key in sourceKeys(id, source) }) {
            return@synchronized false
        }
        // Negative IDs cannot collide with DownloadManager's positive IDs.
        var id = -System.currentTimeMillis()
        while (history.contains(id.toString())) id--
        if (!history.edit().putString(id.toString(), url.toString())
                .putBoolean("pending:$id", true).commit()) {
            throw IOException("Could not record the shared link.")
        }
        true
    }

    fun enqueueResolved(
        url: Uri, source: Uri, replacing: Long?, title: String?, slot: Int, position: String?,
        sharedSource: Uri? = null, folder: String? = null
    ): Boolean =
        synchronized(changeLock) {
            require(supportedLink(source) && slot >= 0 && (sharedSource == null || supportedLink(sharedSource)))
            if (folder != null && folder.isNotEmpty() && folders().none { it.equals(folder.trim(), true) }) {
                return@synchronized false
            }
            if (replacing != null) {
                val previous = entries(setOf(replacing)).singleOrNull()
                if (previous?.get("state") !in listOf("failed", "cancelled", "pending")) {
                    return@synchronized false
                }
            }
            queue(url, replacing, source, title, slot, position, sharedSource, folder)
        }

    private fun queue(
        url: Uri, replacing: Long? = null, original: Uri = url, title: String? = null,
        slot: Int = 0, position: String? = null, sharedSource: Uri? = null, folder: String? = null
    ): Boolean {
        val image = imageExtension(url)
        require(
            image != null || directVideo(url) ||
                (original != url && url.scheme == "https" && url.userInfo == null &&
                    ((url.host?.endsWith(".googlevideo.com") == true && url.path == "/videoplayback" &&
                    url.getQueryParameter("mime") == "video/mp4") || (tikTokLink(original) && tikTokMedia(url))))
        )
        val source = original.toString()
        val rows = sourceRows()
        val requestedKeys = setOfNotNull(downloadKey(original), sharedSource?.let(::downloadKey))
        val pending = rows.filter { (id, value) ->
            history.getBoolean("pending:$id", false) &&
                (id == replacing || sourceKeys(id, value).any { it in requestedKeys })
        }.keys
        val replacement = replacing ?: pending.firstOrNull()
        val removed = pending + setOfNotNull(replacing)
        val aliases = requestedKeys + removed.flatMap { id ->
            rows[id]?.let { sourceKeys(id, it) }.orEmpty()
        }
        val matching = rows.filter { (id, value) ->
            id !in removed && history.getInt("slot:$id", 0) == slot &&
                sourceKeys(id, value).any { it in aliases }
        }.keys
        val existing = entries(matching).firstOrNull { it["state"] in listOf("downloading", "saved") }
        if (existing != null) {
            val id = (existing.getValue("id") as String).toLong()
            val edit = history.edit().putStringSet("aliases:$id", sourceKeys(id, rows.getValue(id)) + aliases)
            pending.forEach { removeMetadata(edit, it) }
            if (!edit.commit()) throw IOException("Could not record the resolved link.")
            // Remember newly learned aliases even for duplicate pastes. Only consuming a
            // pending row completes an operation; an already-present duplicate returns false.
            return pending.isNotEmpty()
        }

        val targetFolder = if (folder != null) {
            if (folder.isEmpty()) "" else folders().singleOrNull { it.equals(folder.trim(), true) }
                ?: return false
        } else if (replacement != null) {
            history.getString("folder:$replacement", "").orEmpty()
        } else {
            // A pending post expands one slide at a time. Its first queued slide carries
            // the folder forward for later slides, independent of their slot numbers.
            rows.entries.firstNotNullOfOrNull { (previousId, previousSource) ->
                history.getString("folder:$previousId", "")?.takeIf { it.isNotEmpty() &&
                    sourceKeys(previousId, previousSource).any { key -> key in aliases }
                }
            }.orEmpty()
        }

        val request = DownloadManager.Request(url.normalizeScheme())
            .setTitle(title ?: "ClipShare download")
            .setDestinationInExternalFilesDir(
                context, directory(image), "${UUID.randomUUID()}.${image ?: "mp4"}"
            )
        if (tikTokLink(original)) {
            request.addRequestHeader("Referer", "https://www.tiktok.com/")
                .addRequestHeader("User-Agent", "ClipShare/0.2")
        }
        val id = enqueueTransfer?.invoke(request) ?: manager.enqueue(request)
        val edit = history.edit().putString(id.toString(), source)
        if (image != null) edit.putString("image:$id", image)
        if (title != null) edit.putString("title:$id", title)
        edit.putInt("slot:$id", slot)
        edit.putStringSet("aliases:$id", aliases)
        if (position != null) edit.putString("position:$id", position)
        edit.putString("folder:$id", targetFolder)
        removed.forEach { removeMetadata(edit, it) }
        if (!edit.commit()) {
            manager.remove(id)
            throw IOException("Could not record the download.")
        }
        removed.filter { it > 0 }.forEach { manager.remove(it) }
        return true
    }

    private fun sourceRows(): Map<Long, String> = history.all.mapNotNull { (key, value) ->
        key.toLongOrNull()?.takeIf { value is String }?.let { it to value as String }
    }.toMap()

    private fun sourceKeys(id: Long, source: String): Set<String> =
        history.getStringSet("aliases:$id", emptySet()).orEmpty() + downloadKey(Uri.parse(source))

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

    fun entries(only: Set<Long>? = null): List<Map<String, Any>> = synchronized(changeLock) {
        val sources = history.all.mapNotNull { (key, value) ->
            val id = key.toLongOrNull()
            if (id == null || value !is String || (only != null && id !in only)) null else id to value
        }.toMap()
        if (sources.isEmpty()) return@synchronized emptyList()

        val states = mutableMapOf<Long, String>()
        val progress = mutableMapOf<Long, Double>()
        val sizes = mutableMapOf<Long, Long>()
        val errors = mutableMapOf<Long, String>()
        manager.query(DownloadManager.Query().setFilterById(*sources.keys.toLongArray())).use { row ->
            val idColumn = row.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)
            val statusColumn = row.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            val receivedColumn = row.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            val totalColumn = row.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            val reasonColumn = row.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)
            while (row.moveToNext()) {
                val id = row.getLong(idColumn)
                val status = row.getInt(statusColumn)
                states[id] = when (status) {
                    DownloadManager.STATUS_SUCCESSFUL -> if (validMedia(id)) "saved" else "failed"
                    DownloadManager.STATUS_FAILED -> "failed"
                    else -> "downloading"
                }
                val total = row.getLong(totalColumn)
                sizes[id] = localFile(id)?.takeIf { it.isFile }?.length()
                    ?: if (status in listOf(DownloadManager.STATUS_PENDING, DownloadManager.STATUS_RUNNING,
                            DownloadManager.STATUS_PAUSED)) maxOf(0L, row.getLong(receivedColumn)) else 0L
                val reason = row.getInt(reasonColumn)
                when {
                    status == DownloadManager.STATUS_SUCCESSFUL && states[id] == "failed" ->
                        errors[id] = if (localFile(id)?.isFile == true) "invalid_media" else "file_missing"
                    status == DownloadManager.STATUS_FAILED -> errors[id] = failureReason(reason)
                    status == DownloadManager.STATUS_PAUSED -> errors[id] = when (reason) {
                        DownloadManager.PAUSED_QUEUED_FOR_WIFI -> "waiting_for_wifi"
                        DownloadManager.PAUSED_WAITING_FOR_NETWORK -> "waiting_for_network"
                        DownloadManager.PAUSED_WAITING_TO_RETRY -> "waiting_to_retry"
                        else -> "download_paused"
                    }
                }
                if (states[id] == "downloading" && total > 0) {
                    progress[id] = (row.getLong(receivedColumn).toDouble() / total).coerceIn(0.0, 1.0)
                }
            }
        }
        sources.entries.sortedByDescending { if (it.key < 0) -it.key else it.key }.map { (id, url) ->
            val state = transferState?.invoke(id) ?: when {
                history.getBoolean("pending:$id", false) -> "pending"
                history.getBoolean("cancelled:$id", false) -> "cancelled"
                else -> states[id] ?: "failed"
            }
            buildMap {
                put("id", id.toString())
                put("url", url)
                put("state", state)
                put("canCancel", state == "downloading")
                put("canRetry", state == "cancelled" || state == "failed")
                put("canExport", state == "saved" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                put("isImage", imageType(id) != null)
                put("folder", history.getString("folder:$id", "").orEmpty())
                put("sizeBytes", sizes[id] ?: 0L)
                (errors[id] ?: if (state == "failed") "download_missing" else null)?.let { put("error", it) }
                history.getString("title:$id", null)?.let { put("title", it) }
                put("slot", history.getInt("slot:$id", 0))
                history.getString("position:$id", null)?.let { put("position", it) }
                progress[id]?.let { put("progress", it) }
            }
        }
    }

    private fun failureReason(reason: Int): String = when (reason) {
        DownloadManager.ERROR_INSUFFICIENT_SPACE -> "storage_full"
        DownloadManager.ERROR_DEVICE_NOT_FOUND -> "storage_unavailable"
        DownloadManager.ERROR_FILE_ERROR -> "file_error"
        DownloadManager.ERROR_HTTP_DATA_ERROR -> "network_error"
        DownloadManager.ERROR_TOO_MANY_REDIRECTS -> "too_many_redirects"
        DownloadManager.ERROR_CANNOT_RESUME -> "cannot_resume"
        DownloadManager.ERROR_FILE_ALREADY_EXISTS -> "file_exists"
        in 400..499 -> "source_unavailable"
        in 500..599 -> "server_error"
        else -> "download_failed"
    }

    private fun removeMetadata(edit: android.content.SharedPreferences.Editor, id: Long) {
        edit.remove(id.toString())
        for (prefix in listOf("cancelled", "pending", "image", "title", "slot", "position", "folder", "aliases")) {
            edit.remove("$prefix:$id")
        }
        validated.remove(id)
    }

    fun folders(): List<String> = synchronized(changeLock) {
        history.getStringSet("folders", emptySet()).orEmpty().sortedWith(String.CASE_INSENSITIVE_ORDER)
    }

    private fun folderName(value: String): String? {
        val name = value.trim()
        return name.takeIf {
            it.length in 1..60 && it.none { character -> character.isISOControl() || character == '/' || character == '\\' } &&
                !it.equals("All downloads", ignoreCase = true) && !it.equals("Unfiled", ignoreCase = true)
        }
    }

    fun createFolder(value: String): Boolean = synchronized(changeLock) {
        val name = folderName(value) ?: return@synchronized false
        val names = folders()
        if (names.any { it.equals(name, ignoreCase = true) }) return@synchronized false
        history.edit().putStringSet("folders", (names + name).toSet()).commit()
    }

    fun renameFolder(from: String, to: String): Boolean = synchronized(changeLock) {
        val names = folders()
        val previous = names.singleOrNull { it.equals(from.trim(), ignoreCase = true) }
            ?: return@synchronized false
        val next = folderName(to) ?: return@synchronized false
        if (names.any { it != previous && it.equals(next, ignoreCase = true) }) return@synchronized false
        val edit = history.edit().putStringSet("folders", (names - previous + next).toSet())
        history.all.forEach { (key, value) ->
            if (key.startsWith("folder:") && value == previous) edit.putString(key, next)
        }
        edit.commit()
    }

    fun deleteFolder(value: String): Boolean = synchronized(changeLock) {
        val names = folders()
        val name = names.singleOrNull { it.equals(value.trim(), ignoreCase = true) }
            ?: return@synchronized false
        val edit = history.edit().putStringSet("folders", (names - name).toSet())
        history.all.forEach { (key, folder) ->
            if (key.startsWith("folder:") && folder == name) edit.remove(key)
        }
        edit.commit()
    }

    fun move(ids: List<Long>, folder: String): Boolean = synchronized(changeLock) {
        val clean = folder.trim()
        val target = if (clean.isEmpty()) "" else folders().singleOrNull { it.equals(clean, true) }
            ?: return@synchronized false
        if (ids.isEmpty() || ids.any { !tracks(it) }) return@synchronized false
        val edit = history.edit()
        ids.toSet().forEach { edit.putString("folder:$it", target) }
        edit.commit()
    }

    fun delete(id: Long): Boolean = synchronized(changeLock) {
        if (!tracks(id)) return@synchronized false
        // DownloadManager owns only the app-local destinations, never Gallery exports.
        if (id > 0) manager.remove(id)
        val edit = history.edit()
        removeMetadata(edit, id)
        edit.commit()
    }

    fun reconcile(): Boolean = synchronized(changeLock) {
        entries() // Re-query DownloadManager and verify successful files on launch.
        true
    }

    @Suppress("DEPRECATION")
    fun info(): Map<String, Any> = synchronized(changeLock) {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val bytes = context.getExternalFilesDirs(null).filterNotNull().sumOf { root ->
            root.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        }
        mapOf(
            "version" to (packageInfo.versionName ?: ""),
            "build" to if (Build.VERSION.SDK_INT >= 28) packageInfo.longVersionCode.toString()
                else packageInfo.versionCode.toString(),
            "os" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "storageBytes" to bytes,
            "recoveredEntries" to 0
        )
    }

    private fun localFile(id: Long): File? {
        if (id <= 0) return null
        return try {
            manager.query(DownloadManager.Query().setFilterById(id)).use { row ->
                if (!row.moveToFirst()) return null
                val uri = Uri.parse(row.getString(row.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)) ?: return null)
                if (uri.scheme != "file") return null
                val file = File(uri.path ?: return null).canonicalFile
                if (context.getExternalFilesDirs(null).filterNotNull().none {
                        file.path.startsWith(it.canonicalPath + java.io.File.separator)
                    }) return null
                file
            }
        } catch (error: Exception) { null }
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
        when (image) {
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "image/jpeg"
        }

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

    private fun validMedia(id: Long): Boolean = validateFile(id, localFile(id)) { decodeMedia(id) }

    private fun decodeMedia(id: Long): Boolean {
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
