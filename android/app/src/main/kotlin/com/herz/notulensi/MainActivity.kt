package com.herz.notulensi

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity: FlutterActivity() {
    private val RECORDING_CHANNEL = "com.herz.notulensi/recording"
    private val FILES_CHANNEL = "com.herz.notulensi/files"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDING_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecordingService" -> {
                    // 1. Keep screen on while recording so it doesn't sleep automatically on the table
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

                    // 2. Start Foreground Service so microphone stays unmuted if user manually turns off screen
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
                    // 1. Restore normal screen timeout
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

                    // 2. Stop Foreground Service
                    val intent = Intent(this, RecordingForegroundService::class.java).apply {
                        action = RecordingForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "savePdfToDownloads" -> {
                    val filePath = call.argument<String>("filePath")
                    val fileName = call.argument<String>("fileName") ?: "Notulensi_HerzNote.pdf"
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
                else -> result.notImplemented()
            }
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
