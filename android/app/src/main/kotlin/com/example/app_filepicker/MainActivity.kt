package com.example.app_filepicker

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.usage.StorageStatsManager
import android.content.Context
import android.os.Build
import android.os.storage.StorageManager
import android.os.Environment
import android.os.StatFs
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.graphics.Bitmap
import android.util.Size
import android.provider.MediaStore
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.HashMap
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.app_filepicker/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "getStorageInfo" -> {
                    var totalSize: Long = 0
                    var availableSize: Long = 0

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val storageStatsManager = getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
                            totalSize = storageStatsManager.getTotalBytes(StorageManager.UUID_DEFAULT)
                            availableSize = storageStatsManager.getFreeBytes(StorageManager.UUID_DEFAULT)
                        } catch (e: Exception) {
                            val path = Environment.getExternalStorageDirectory()
                            val stat = StatFs(path.path)
                            totalSize = stat.blockCountLong * stat.blockSizeLong
                            availableSize = stat.availableBlocksLong * stat.blockSizeLong
                        }
                    } else {
                        val path = Environment.getExternalStorageDirectory()
                        val stat = StatFs(path.path)
                        totalSize = stat.blockCountLong * stat.blockSizeLong
                        availableSize = stat.availableBlocksLong * stat.blockSizeLong
                    }

                    val map = HashMap<String, Long>()
                    map["total"] = totalSize
                    map["available"] = availableSize
                    result.success(map)
                }
                "getMediaThumbnail" -> {
                    val path = call.argument<String>("path")
                    val type = call.argument<String>("type")
                    if (path == null) {
                        result.error("INVALID_ARGUMENT", "Path is null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        var bitmap: Bitmap? = null
                        if (type == "video") {
                            bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                ThumbnailUtils.createVideoThumbnail(File(path), Size(300, 300), null)
                            } else {
                                ThumbnailUtils.createVideoThumbnail(path, MediaStore.Video.Thumbnails.MINI_KIND)
                            }
                        } else if (type == "audio") {
                            val retriever = MediaMetadataRetriever()
                            retriever.setDataSource(path)
                            val art = retriever.embeddedPicture
                            retriever.release()
                            if (art != null) {
                                result.success(art)
                                return@setMethodCallHandler
                            }
                        }

                        if (bitmap != null) {
                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)
                            result.success(stream.toByteArray())
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        android.media.MediaScannerConnection.scanFile(this, arrayOf(path), null) { _, _ -> }
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Path is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
