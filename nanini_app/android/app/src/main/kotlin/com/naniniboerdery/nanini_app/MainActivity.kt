package com.naniniboerdery.nanini_app

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Own subclass so its manifest entry can't clash with a plugin's FileProvider. */
class UpdateFileProvider : FileProvider()

class MainActivity : FlutterActivity() {
    // In-app updates (lib/core/update/app_updater.dart). The new APK is
    // fetched by Android's own DownloadManager, which keeps going with the
    // app in the background or the screen off, resumes after the signal
    // drops, and shows its progress in the notifications. Then Android is
    // asked to install it.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nanini/update").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "updatesDir" -> result.success(File(cacheDir, "updates").apply { mkdirs() }.absolutePath)
                    "download" -> result.success(startDownload(call.argument<String>("url")!!, call.argument<String>("fileName")!!, call.argument<Boolean>("wifiOnly") == true))
                    "downloadStatus" -> result.success(downloadStatus(call.argument<Number>("id")!!.toLong()))
                    "cancelDownload" -> {
                        downloads().remove(call.argument<Number>("id")!!.toLong())
                        result.success(null)
                    }
                    "install" -> result.success(install(File(call.argument<String>("path")!!)))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error(call.method, e.message, null)
            }
        }
    }

    private fun downloads() = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    private fun startDownload(url: String, fileName: String, wifiOnly: Boolean): Long {
        // Into the app's own folder: no storage permission needed.
        val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: throw IllegalStateException("No storage")
        File(dir, fileName).delete()
        val label = applicationInfo.loadLabel(packageManager)
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle("$label update")
            .setDescription("Downloading the new version")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, fileName)
            .setAllowedOverMetered(!wifiOnly)
            .setAllowedOverRoaming(false)
        return downloads().enqueue(request)
    }

    /** {status: pending|running|paused|done|failed|missing, got, total, path, reason}. */
    private fun downloadStatus(id: Long): Map<String, Any?> {
        downloads().query(DownloadManager.Query().setFilterById(id)).use { c ->
            if (!c.moveToFirst()) return mapOf("status" to "missing")
            fun long(col: String) = c.getLong(c.getColumnIndexOrThrow(col))
            val status = when (c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                DownloadManager.STATUS_PENDING -> "pending"
                DownloadManager.STATUS_RUNNING -> "running"
                DownloadManager.STATUS_PAUSED -> "paused"
                DownloadManager.STATUS_SUCCESSFUL -> "done"
                else -> "failed"
            }
            val local = c.getString(c.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
            return mapOf(
                "status" to status,
                "got" to long(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                "total" to long(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
                "path" to local?.let { Uri.parse(it).path },
                "reason" to long(DownloadManager.COLUMN_REASON),
            )
        }
    }

    private fun install(file: File): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            // First time: the phone must allow this app to install updates.
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            return "permission"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        })
        return "started"
    }
}
