package com.adesmith001.clipshare

import android.net.Uri
import android.test.AndroidTestCase
import java.io.File

/** Runs on a device without third-party test dependencies or network access. */
@Suppress("DEPRECATION")
class AndroidDownloadsTest : AndroidTestCase() {
    fun testTikTokSharesResolveExtensionlessVideosAndRememberAliases() {
        val created = mutableListOf<Long>()
        val downloads = AndroidDownloads(context, enqueueTransfer = {
            (Long.MAX_VALUE - 4000 - created.size).also { created += it }
        }, transferState = { "downloading" })
        val stamp = System.nanoTime().toString()
        val source = Uri.parse("https://www.tiktok.com/@_/video/$stamp")
        val shared = Uri.parse("https://vm.tiktok.com/Z$stamp/")
        val media = Uri.parse("https://v16.tiktokcdn-us.com/video/clip/?signature=example")
        var pending: Long? = null
        try {
            assertTrue(AndroidDownloads.socialLink(source))
            assertTrue(AndroidDownloads.socialLink(shared))
            assertTrue(AndroidDownloads.socialLink(Uri.parse("https://www.tiktok.com/t/Z$stamp/")))
            assertFalse(AndroidDownloads.socialLink(Uri.parse("https://www.tiktok.com/@creator/photo/$stamp")))
            assertFalse(AndroidDownloads.socialLink(Uri.parse("https://vm.tiktok.com.evil.test/Z$stamp")))
            assertTrue(AndroidDownloads.tikTokMedia(media))
            assertFalse(AndroidDownloads.tikTokMedia(Uri.parse("https://v16.tiktokcdn-us.com.evil.test/video/clip/")))
            assertTrue(downloads.enqueue(shared))
            pending = downloads.entries().single { it["url"] == shared.toString() }["id"].toString().toLong()
            assertTrue(downloads.enqueueResolved(media, source, pending, "TikTok", 0, null, sharedSource = shared))
            assertFalse(downloads.tracks(pending))
            assertFalse(downloads.enqueue(shared))
            assertFalse(downloads.enqueue(Uri.parse("https://www.tiktok.com/@another/video/$stamp?tracking=other")))
            assertEquals(1, created.size)
        } finally {
            pending?.let(downloads::delete)
            created.forEach(downloads::delete)
        }
    }

    fun testSharedPostAndFolderMutationsArePersistentAndAtomic() {
        val downloads = AndroidDownloads(context)
        val suffix = System.currentTimeMillis().toString()
        val folder = "Test $suffix"
        val renamed = "Renamed $suffix"
        var id: Long? = null
        try {
            val source = Uri.parse("https://x.com/clipshare_test/status/$suffix?tracking=first")
            assertTrue(downloads.enqueue(source))
            assertFalse(downloads.enqueue(Uri.parse("https://twitter.com/clipshare_test/status/$suffix?tracking=second")))
            assertFalse(downloads.enqueue(source))
            val pending = downloads.entries().single { it["url"] == source.toString() }
            id = (pending.getValue("id") as String).toLong()
            assertEquals("pending", pending["state"])
            assertTrue(id < 0)
            assertTrue(downloads.createFolder("  $folder  "))
            assertFalse(downloads.createFolder(folder.uppercase()))
            assertFalse(downloads.createFolder("Unfiled"))
            assertFalse(downloads.createFolder("All downloads"))
            assertFalse(downloads.move(listOf(id, Long.MIN_VALUE), folder))
            assertEquals("", downloads.entries(setOf(id)).single()["folder"])
            assertTrue(downloads.move(listOf(id), folder))
            assertTrue(downloads.renameFolder(folder, renamed))
            val reopened = AndroidDownloads(context)
            assertEquals(renamed, reopened.entries(setOf(id)).single()["folder"])
            assertTrue(reopened.deleteFolder(renamed))
            assertEquals("", reopened.entries(setOf(id)).single()["folder"])
            assertTrue(reopened.delete(id))
            assertFalse(reopened.tracks(id))
        } finally {
            id?.let(downloads::delete)
            downloads.deleteFolder(folder)
            downloads.deleteFolder(renamed)
        }
    }

    fun testSupportedPostLinksRejectLookalikeHostsAndUnsupportedPages() {
        listOf(
            "https://x.com/user/status/123", "https://x.com/i/web/status/123",
            "https://www.instagram.com/p/abc_123/", "https://www.pinterest.com/pin/123/",
            "https://pin.it/abc", "https://www.instagram.com/reel/abc_123/",
            "https://youtu.be/dQw4w9WgXc", "https://www.youtube.com/watch?v=dQw4w9WgXc"
        ).forEach { assertTrue(it, AndroidDownloads.socialLink(Uri.parse(it))) }
        listOf(
            "https://x.com.evil.test/user/status/123", "https://pinterest.com.evil.test/pin/123/",
            "https://www.instagram.com/accounts/login/", "https://youtube.com/@channel",
            "http://x.com/user/status/123", "https://name:secret@x.com/user/status/123"
        ).forEach { assertFalse(it, AndroidDownloads.supportedLink(Uri.parse(it))) }
    }
    fun testResolvedPastesConsumePendingAndRetainShortlinkAliases() {
        val states = mutableMapOf<Long, String>()
        val created = mutableListOf<Long>()
        val downloads = AndroidDownloads(context, enqueueTransfer = {
            (Long.MAX_VALUE - created.size).also { id -> created += id; states[id] = "downloading" }
        }, transferState = states::get)
        val stamp = System.nanoTime().toString()
        val folder = "Resolve $stamp"
        val media = Uri.parse("https://media.example.test/$stamp.mp4")
        val canonical = Uri.parse("https://www.pinterest.com/pin/$stamp/")
        val short = Uri.parse("https://pin.it/a$stamp")
        val redundantShort = Uri.parse("https://pin.it/b$stamp")
        val pastedAlias = Uri.parse("https://pin.it/c$stamp")
        val pendingIds = mutableListOf<Long>()
        try {
            assertTrue(downloads.createFolder(folder))
            assertTrue(downloads.enqueue(short))
            val pending = downloads.entries().single { it["url"] == short.toString() }["id"].toString().toLong()
            pendingIds += pending
            assertTrue(downloads.move(listOf(pending), folder))
            // Pasting a raw shortlink resolves to a different canonical source, without an explicit replacement.
            assertTrue(downloads.enqueueResolved(media, canonical, null, null, 0, null, sharedSource = short))
            assertFalse(downloads.tracks(pending))
            assertEquals(1, created.size)
            assertEquals(folder, downloads.entries(setOf(created.single())).single()["folder"])
            assertFalse(AndroidDownloads(context).enqueue(short))
            assertFalse(downloads.enqueueResolved(media, canonical, null, null, 0, null, sharedSource = short))
            assertEquals(1, created.size)

            // A second unknown alias becomes pending, then resolves to already saved canonical media.
            states[created.single()] = "saved"
            assertTrue(downloads.enqueue(redundantShort))
            val redundant = downloads.entries().single { it["url"] == redundantShort.toString() }["id"].toString().toLong()
            pendingIds += redundant
            assertTrue(downloads.enqueueResolved(media, canonical, redundant, null, 0, null, sharedSource = redundantShort))
            assertFalse(downloads.tracks(redundant))
            assertFalse(AndroidDownloads(context).enqueue(redundantShort))
            assertEquals(1, created.size)

            // An alias first learned from a duplicate paste has no pending row to consume.
            assertFalse(downloads.enqueueResolved(media, canonical, null, null, 0, null, sharedSource = pastedAlias))
            assertFalse(AndroidDownloads(context).enqueue(pastedAlias))
            assertEquals(1, created.size)

            // Canonical X forms emitted by Dart match the original Twitter pending identity.
            val sharedX = Uri.parse("https://twitter.com/user/status/$stamp")
            val canonicalX = Uri.parse("https://x.com/i/web/status/$stamp")
            assertTrue(downloads.enqueue(sharedX))
            val xPending = downloads.entries().single { it["url"] == sharedX.toString() }["id"].toString().toLong()
            pendingIds += xPending
            assertTrue(downloads.enqueueResolved(media, canonicalX, null, null, 0, null))
            assertFalse(downloads.tracks(xPending))
            assertEquals(2, created.size)
        } finally {
            (created + pendingIds).forEach(downloads::delete)
            downloads.deleteFolder(folder)
        }
    }

    fun testRetryKeepsFolderAndValidationCachesBothOutcomesUntilFileChanges() {
        val states = mutableMapOf<Long, String>()
        val created = mutableListOf<Long>()
        val downloads = AndroidDownloads(context, enqueueTransfer = {
            (Long.MAX_VALUE - 100 - created.size).also { id -> created += id; states[id] = "downloading" }
        }, transferState = states::get)
        val stamp = System.nanoTime().toString()
        val folder = "Retry $stamp"
        val file = File(context.cacheDir, "validation-$stamp")
        val validationId = -System.nanoTime()
        try {
            assertTrue(downloads.createFolder(folder))
            assertTrue(downloads.enqueue(Uri.parse("https://media.example.test/$stamp.mp4")))
            val previous = created.single()
            assertTrue(downloads.move(listOf(previous), folder))
            states[previous] = "failed"
            assertTrue(downloads.retry(previous))
            assertFalse(downloads.tracks(previous))
            assertEquals(folder, downloads.entries(setOf(created.last())).single()["folder"])
            var decodes = 0
            file.writeText("invalid")
            assertFalse(AndroidDownloads.validateFile(validationId, file) { decodes++; false })
            assertFalse(AndroidDownloads.validateFile(validationId, file) { decodes++; true })
            assertEquals(1, decodes)
            file.appendText(" changed")
            assertTrue(AndroidDownloads.validateFile(validationId, file) { decodes++; true })
            assertTrue(AndroidDownloads.validateFile(validationId, file) { decodes++; false })
            assertEquals(2, decodes)
            assertTrue(file.delete())
            assertFalse(AndroidDownloads.validateFile(validationId, file) { decodes++; true })
            assertEquals(2, decodes)
        } finally {
            created.forEach(downloads::delete)
            downloads.deleteFolder(folder)
            file.delete()
            AndroidDownloads.validateFile(validationId, null) { false }
        }
    }

    fun testResolvedSlidesSharePendingFolderAndExplicitUnfiledRetryStaysUnfiled() {
        val states = mutableMapOf<Long, String>()
        val created = mutableListOf<Long>()
        val downloads = AndroidDownloads(context, enqueueTransfer = {
            (Long.MAX_VALUE - 200 - created.size).also { id -> created += id; states[id] = "downloading" }
        }, transferState = states::get)
        val stamp = System.nanoTime().toString()
        val folder = "Travel $stamp"
        val shared = Uri.parse("https://www.instagram.com/reel/slides_$stamp/")
        val canonical = Uri.parse("https://www.instagram.com/p/slides_$stamp/")
        val media = Uri.parse("https://media.example.test/$stamp.mp4")
        var pending: Long? = null
        try {
            assertTrue(downloads.createFolder(folder))
            assertTrue(downloads.enqueue(shared))
            pending = downloads.entries().single { it["url"] == shared.toString() }["id"].toString().toLong()
            assertTrue(downloads.move(listOf(pending), folder))
            assertTrue(downloads.enqueueResolved(media, canonical, pending, null, 0, "1 of 2", sharedSource = shared))
            assertTrue(downloads.enqueueResolved(media, canonical, null, null, 1, "2 of 2", sharedSource = shared))
            assertEquals(2, created.size)
            val slides = downloads.entries(created.toSet())
            assertEquals(setOf(folder), slides.map { it["folder"] }.toSet())
            assertEquals(setOf(0, 1), slides.map { it["slot"] }.toSet())

            // A sibling's folder must not override an explicit replacement that is Unfiled.
            val unfiled = created.last()
            assertTrue(downloads.move(listOf(unfiled), ""))
            states[unfiled] = "failed"
            assertTrue(downloads.enqueueResolved(media, canonical, unfiled, null, 1, "2 of 2", sharedSource = shared))
            assertEquals("", downloads.entries(setOf(created.last())).single()["folder"])
            assertEquals(folder, downloads.entries(setOf(created.first())).single()["folder"])
        } finally {
            (created + listOfNotNull(pending)).forEach(downloads::delete)
            downloads.deleteFolder(folder)
        }
    }

    fun testExplicitUnfiledForNewSlideDoesNotMoveExistingDuplicate() {
        val states = mutableMapOf<Long, String>()
        val created = mutableListOf<Long>()
        val downloads = AndroidDownloads(context, enqueueTransfer = {
            (Long.MAX_VALUE - 300 - created.size).also { id -> created += id; states[id] = "downloading" }
        }, transferState = states::get)
        val stamp = System.nanoTime().toString()
        val trips = "Trips $stamp"
        val source = Uri.parse("https://www.pinterest.com/pin/$stamp/")
        val shared = Uri.parse("https://pin.it/mixed$stamp")
        val media = Uri.parse("https://media.example.test/$stamp.mp4")
        var pending: Long? = null
        try {
            assertTrue(downloads.createFolder(trips))
            assertTrue(downloads.enqueueResolved(media, source, null, null, 0, "1 of 2", folder = trips))
            val existing = created.single()
            states[existing] = "saved"
            assertTrue(downloads.enqueue(shared))
            pending = downloads.entries().single { it["url"] == shared.toString() }["id"].toString().toLong()
            assertEquals("", downloads.entries(setOf(pending)).single()["folder"])
            assertTrue(downloads.enqueueResolved(media, source, pending, null, 0, "1 of 2", sharedSource = shared, folder = ""))
            assertFalse(downloads.tracks(pending))
            assertEquals(1, created.size)
            assertTrue(downloads.enqueueResolved(media, source, null, null, 1, "2 of 2", sharedSource = shared, folder = ""))
            assertEquals(trips, downloads.entries(setOf(existing)).single()["folder"])
            assertEquals("", downloads.entries(setOf(created.last())).single()["folder"])
            assertFalse(downloads.enqueueResolved(media, source, null, null, 2, "3 of 3", folder = "Missing $stamp"))
            assertEquals(2, created.size)
        } finally {
            (created + listOfNotNull(pending)).forEach(downloads::delete)
            downloads.deleteFolder(trips)
        }
    }

}
