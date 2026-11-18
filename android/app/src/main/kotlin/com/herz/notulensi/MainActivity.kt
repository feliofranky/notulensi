package com.herz.notulensi

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val RECORDING_CHANNEL = "com.herz.notulensi/recording"
    private val FILES_CHANNEL = "com.herz.notulensi/files"
    private val PLAYER_CHANNEL = "com.herz.notulensi/audio_player"

    private val REQ_PICK_AUDIO = 4091
    private var pendingAudioPickResult: MethodChannel.Result? = null
    private var pendingAudioDestDir: String? = null

    private var mediaPlayer: MediaPlayer? = null
    private var loadedAudioPath: String? = null
    private var currentPlaybackSpeed: Float = 1.0f

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Recording Foreground Service & WakeLock Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDING_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecordingService" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    val intent = Intent(this, RecordingForegroundService::class.java).apply {
                        action = RecordingForegroundService.ACTION_START
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopRecordingService" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    val intent = Intent(this, RecordingForegroundService::class.java).apply {
                        action = RecordingForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 2. Files Channel (Save PDF to Download, Open PDF, Pick External Audio)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "savePdfToDownloads" -> {
                    val filePath = call.argument<String>("filePath")
                    val fileName = call.argument<String>("fileName") ?: "Notulensi_HERZnote.pdf"
                    if (filePath.isNullOrEmpty()) {
                        result.error("INVALID_ARGS", "Path file PDF kosong", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val savedUri = saveFileToDownloads(filePath, fileName)
                        result.success(savedUri)
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", e.message ?: "Gagal menyimpan PDF ke Download", null)
                    }
                }
                "openPdfUri" -> {
                    val uriStr = call.argument<String>("uri")
                    if (uriStr.isNullOrEmpty()) {
                        result.error("INVALID_ARGS", "URI file kosong", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(uriStr)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/pdf")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(Intent.createChooser(intent, "Buka PDF dengan"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_ERROR", e.message ?: "Tidak ada aplikasi pembuka PDF", null)
                    }
                }
                "pickAudioFile" -> {
                    if (pendingAudioPickResult != null) {
                        result.error("ALREADY_ACTIVE", "Pemilih file sedang terbuka", null)
                        return@setMethodCallHandler
                    }
                    pendingAudioDestDir = call.argument<String>("destDir")
                    pendingAudioPickResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "audio/*"
                            putExtra(
                                Intent.EXTRA_MIME_TYPES,
                                arrayOf(
                                    "audio/*",
                                    "application/ogg",
                                    "audio/ogg",
                                    "audio/opus",
                                    "audio/mpeg",
                                    "audio/mp4",
                                    "audio/x-wav",
                                    "audio/wav"
                                )
                            )
                        }
                        startActivityForResult(intent, REQ_PICK_AUDIO)
                    } catch (e: Exception) {
                        pendingAudioPickResult = null
                        result.error("PICK_ERROR", e.message ?: "Gagal membuka pemilih audio", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 3. Native Mini Audio Player Channel (Zero extra plugins, plays WAV/MP3/M4A/OGG/OPUS)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAYER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val path = call.argument<String>("path")
                    val speedArg = call.argument<Double>("speed")
                    if (speedArg != null) {
                        currentPlaybackSpeed = speedArg.toFloat().coerceIn(0.5f, 2.5f)
                    }
                    if (path.isNullOrEmpty()) {
                        result.error("INVALID_PATH", "Path audio kosong", null)
                        return@setMethodCallHandler
                    }
                    try {
                        if (mediaPlayer == null || loadedAudioPath != path) {
                            releasePlayer()
                            val mp = MediaPlayer()
                            mp.setDataSource(path)
                            mp.prepare()
                            mediaPlayer = mp
                            loadedAudioPath = path
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            mediaPlayer?.let { mp ->
                                mp.playbackParams = mp.playbackParams.setSpeed(currentPlaybackSpeed)
                            }
                        }
                        if (mediaPlayer?.isPlaying != true) {
                            mediaPlayer?.start()
                        }
                        result.success(getPlayerStatus())
                    } catch (e: Exception) {
                        releasePlayer()
                        result.error("PLAY_ERROR", e.message ?: "Gagal memutar audio", null)
                    }
                }
                "setSpeed" -> {
                    val speedArg = call.argument<Double>("speed") ?: 1.0
                    currentPlaybackSpeed = speedArg.toFloat().coerceIn(0.5f, 2.5f)
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            mediaPlayer?.let { mp ->
                                val wasPlaying = mp.isPlaying
                                mp.playbackParams = mp.playbackParams.setSpeed(currentPlaybackSpeed)
                                if (!wasPlaying && mp.isPlaying) {
                                    mp.pause()
                                }
                            }
                        }
                        result.success(getPlayerStatus())
                    } catch (e: Exception) {
                        result.success(getPlayerStatus())
                    }
                }
                "pause" -> {
                    try {
                        if (mediaPlayer?.isPlaying == true) {
                            mediaPlayer?.pause()
                        }
                        result.success(getPlayerStatus())
                    } catch (e: Exception) {
                        result.success(getPlayerStatus())
                    }
                }
                "seek" -> {
                    val posMs = call.argument<Int>("positionMs") ?: 0
                    try {
                        mediaPlayer?.seekTo(posMs)
                        result.success(getPlayerStatus())
                    } catch (e: Exception) {
                        result.success(getPlayerStatus())
                    }
                }
                "getStatus" -> {
                    result.success(getPlayerStatus())
                }
                "stop" -> {
                    releasePlayer()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getPlayerStatus(): Map<String, Any> {
        val mp = mediaPlayer ?: return mapOf("isPlaying" to false, "positionMs" to 0, "durationMs" to 0)
        return try {
            mapOf(
                "isPlaying" to mp.isPlaying,
                "positionMs" to mp.currentPosition,
                "durationMs" to mp.duration
            )
        } catch (_: Exception) {
            mapOf("isPlaying" to false, "positionMs" to 0, "durationMs" to 0)
        }
    }

    private fun releasePlayer() {
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {}
        try {
            mediaPlayer?.release()
        } catch (_: Exception) {}
        mediaPlayer = null
        loadedAudioPath = null
    }

    override fun onDestroy() {
        releasePlayer()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PICK_AUDIO) {
            val callback = pendingAudioPickResult
            val destDirStr = pendingAudioDestDir
            pendingAudioPickResult = null
            pendingAudioDestDir = null

            if (callback == null) return

            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                callback.success(null)
                return
            }

            val uri = data.data!!
            try {
                val displayName = queryDisplayName(uri) ?: "audio_import.m4a"
                val ext = extractExtension(displayName)
                val targetDir = if (!destDirStr.isNullOrEmpty()) File(destDirStr) else File(filesDir, "recordings")
                if (!targetDir.exists()) targetDir.mkdirs()

                val destFile = File(targetDir, "import_${System.currentTimeMillis()}$ext")
                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(destFile).use { output ->
                        input.copyTo(output)
                    }
                } ?: throw Exception("Tidak dapat membaca file audio yang dipilih")

                val durationSec = extractAudioDurationSeconds(destFile.absolutePath)
                callback.success(
                    mapOf(
                        "path" to destFile.absolutePath,
                        "name" to displayName,
                        "durationSeconds" to durationSec
                    )
                )
            } catch (e: Exception) {
                callback.error("IMPORT_ERROR", e.message ?: "Gagal mengimpor file audio", null)
            }
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun extractExtension(name: String): String {
        val dot = name.lastIndexOf('.')
        if (dot != -1 && dot < name.length - 1) {
            val ext = name.substring(dot).lowercase()
            if (ext.length in 2..6) return ext
        }
        return ".m4a"
    }

    private fun extractAudioDurationSeconds(filePath: String): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(filePath)
            val durStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val durMs = durStr?.toLongOrNull() ?: 0L
            (durMs / 1000L).toInt().coerceAtLeast(1)
        } catch (_: Exception) {
            0
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {}
        }
    }

    private fun saveFileToDownloads(sourcePath: String, fileName: String): String {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw Exception("File sumber PDF tidak ditemukan")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val contentValues = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                ?: throw Exception("Gagal membuat berkas di folder Download")

            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(out)
                }
            } ?: throw Exception("Gagal menulis data PDF")

            contentValues.clear()
            contentValues.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)

            return uri.toString()
        } else {
            @Suppress("DEPRECATION")
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) downloadsDir.mkdirs()
            val destFile = File(downloadsDir, fileName)
            sourceFile.copyTo(destFile, overwrite = true)
            return Uri.fromFile(destFile).toString()
        }
    }
}
