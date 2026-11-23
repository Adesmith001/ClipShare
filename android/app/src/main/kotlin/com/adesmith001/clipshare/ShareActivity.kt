package com.adesmith001.clipshare

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Patterns
import android.widget.Toast

class ShareActivity : Activity() {
    private var confirmation: AlertDialog? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = sharedLink(intent)
        val dialog = AlertDialog.Builder(this)
            .setTitle("ClipShare")
            .setNegativeButton("Cancel", null)
            .setOnDismissListener { finish() }

        if (url == null) {
            dialog.setMessage("Share an X, Pinterest, Instagram, YouTube, TikTok, or direct HTTPS media link.")
        } else {
            val pending = AndroidDownloads.socialLink(url)
            dialog.setMessage(if (pending) "Add this post from ${url.host} to Downloads? Open ClipShare to start it."
                else "Download from ${url.host}?")
                .setPositiveButton(if (pending) "Add" else "Download") { _, _ ->
                    val message = try {
                        if (AndroidDownloads(this).enqueue(url)) {
                            if (pending) "Added to Downloads. Open ClipShare to start." else "Download started"
                        }
                        else "This item is already in Downloads"
                    } catch (error: Exception) {
                        "Couldn’t start the download"
                    }
                    Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
                }
        }
        confirmation = dialog.show()
    }

    override fun onDestroy() {
        confirmation?.setOnDismissListener(null)
        confirmation?.dismiss()
        super.onDestroy()
    }

    private fun sharedLink(intent: Intent): Uri? {
        if (intent.action != Intent.ACTION_SEND || intent.type != "text/plain") return null
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT) ?: return null
        val matcher = Patterns.WEB_URL.matcher(text)
        while (matcher.find()) {
            val url = Uri.parse(matcher.group())
            if (AndroidDownloads.supportedLink(url)) {
                return url.normalizeScheme()
            }
        }
        return null
    }
}
