package iq.edu.nust.nust_student_portal

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL_UPDATER = "iq.edu.nust.mohadarati/updater"
    private val CHANNEL_NOTIFICATIONS = "iq.edu.nust.mohadarati/notifications"
    private val CHANNEL_PDF = "iq.edu.nust.mohadarati/pdf"
    private val NOTIF_CHANNEL_ID = "nust_live_notifications_v1"

    private var currentPdfRenderer: PdfRenderer? = null
    private var currentPfd: ParcelFileDescriptor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

        // 1. قناة التحديثات، التثبيت، وحفظ الملفات في التنزيلات
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_UPDATER).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVersionCode" -> {
                    try {
                        val pInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            context.packageManager.getPackageInfo(context.packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
                        } else {
                            @Suppress("DEPRECATION")
                            context.packageManager.getPackageInfo(context.packageName, 0)
                        }
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pInfo.longVersionCode.toInt()
                        } else {
                            @Suppress("DEPRECATION")
                            pInfo.versionCode
                        }
                        result.success(versionCode)
                    } catch (e: Exception) {
                        result.error("VERSION_ERROR", e.message, null)
                    }
                }
                "getCacheDir" -> {
                    try {
                        result.success(context.cacheDir.absolutePath)
                    } catch (e: Exception) {
                        result.error("CACHE_ERROR", e.message, null)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val file = File(filePath)
                        if (file.exists()) {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                        FileProvider.getUriForFile(
                                            context,
                                            "${context.packageName}.fileprovider",
                                            file
                                        )
                                    } else {
                                        Uri.fromFile(file)
                                    }
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                context.startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("INSTALL_ERROR", e.message, null)
                            }
                        } else {
                            result.error("FILE_NOT_FOUND", "APK file does not exist", null)
                        }
                    } else {
                        result.error("INVALID_PATH", "File path is null", null)
                    }
                }
                "saveToDownloads" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val fileName = call.argument<String>("fileName") ?: "lecture.pdf"
                    if (bytes != null && bytes.isNotEmpty()) {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                val contentValues = ContentValues().apply {
                                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                                    put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/محاضراتي")
                                }
                                val resolver = context.contentResolver
                                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                                if (uri != null) {
                                    resolver.openOutputStream(uri)?.use { it.write(bytes) }
                                    result.success(true)
                                } else {
                                    result.success(false)
                                }
                            } else {
                                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "محاضراتي")
                                if (!dir.exists()) dir.mkdirs()
                                val file = File(dir, fileName)
                                file.writeBytes(bytes)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("SAVE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NO_DATA", "File bytes are null or empty", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 2. قناة إشعارات النظام الفورية لأجهزة الأندرويد
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NOTIFICATIONS).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val isGranted = ContextCompat.checkSelfPermission(
                                this,
                                android.Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED

                            if (!isGranted) {
                                ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                    9901
                                )
                                result.success(false)
                            } else {
                                result.success(true)
                            }
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("PERMISSION_ERROR", e.message, null)
                    }
                }
                "areNotificationsEnabled" -> {
                    try {
                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        var enabled = manager.areNotificationsEnabled()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val isGranted = ContextCompat.checkSelfPermission(
                                this,
                                android.Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED
                            enabled = enabled && isGranted
                        }
                        result.success(enabled)
                    } catch (e: Exception) {
                        result.error("STATUS_ERROR", e.message, null)
                    }
                }
                "showNotification" -> {
                    try {
                        val title = call.argument<String>("title") ?: "محاضراتي"
                        val body = call.argument<String>("body") ?: ""
                        val tag = call.argument<String>("tag") ?: "nust_${System.currentTimeMillis()}"

                        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        } ?: Intent(this, MainActivity::class.java)

                        val flag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        } else {
                            PendingIntent.FLAG_UPDATE_CURRENT
                        }

                        val pendingIntent = PendingIntent.getActivity(
                            this,
                            (System.currentTimeMillis() % 100000).toInt(),
                            intent,
                            flag
                        )

                        val builder = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
                            .setSmallIcon(R.mipmap.ic_launcher)
                            .setContentTitle(title)
                            .setContentText(body)
                            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                            .setPriority(NotificationCompat.PRIORITY_HIGH)
                            .setDefaults(NotificationCompat.DEFAULT_ALL)
                            .setAutoCancel(true)
                            .setContentIntent(pendingIntent)

                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        val notifId = (System.currentTimeMillis() % 1000000).toInt()
                        manager.notify(tag, notifId, builder.build())
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 3. محرك معاينة وقراءة ملفات الـ PDF الأصلي المدمج (In-App Native PDF Renderer)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_PDF).setMethodCallHandler { call, result ->
            when (call.method) {
                "openPdf" -> {
                    synchronized(this) {
                        try {
                            val filePath = call.argument<String>("filePath")
                            if (filePath == null) {
                                result.error("ARG_ERROR", "filePath is required", null)
                                return@setMethodCallHandler
                            }
                            val file = File(filePath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "PDF file does not exist", null)
                                return@setMethodCallHandler
                            }

                            currentPdfRenderer?.close()
                            currentPfd?.close()

                            currentPfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                            currentPdfRenderer = PdfRenderer(currentPfd!!)
                            val pageCount = currentPdfRenderer!!.pageCount

                            result.success(mapOf("pageCount" to pageCount))
                        } catch (e: Exception) {
                            result.error("PDF_OPEN_ERROR", e.message, null)
                        }
                    }
                }
                "renderPage" -> {
                    synchronized(this) {
                        try {
                            val renderer = currentPdfRenderer
                            if (renderer == null) {
                                result.error("NO_PDF", "No PDF currently open", null)
                                return@setMethodCallHandler
                            }
                            val pageIndex = call.argument<Int>("pageIndex") ?: 0
                            val targetWidth = call.argument<Int>("targetWidth") ?: 1080

                            if (pageIndex < 0 || pageIndex >= renderer.pageCount) {
                                result.error("INVALID_PAGE", "Page index out of bounds", null)
                                return@setMethodCallHandler
                            }

                            val page = renderer.openPage(pageIndex)
                            val w = targetWidth.coerceAtLeast(300)
                            val h = ((w.toFloat() / page.width) * page.height).toInt().coerceAtLeast(300)

                            val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                            bitmap.eraseColor(Color.WHITE)
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            page.close()

                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.JPEG, 88, stream)
                            val bytes = stream.toByteArray()
                            bitmap.recycle()

                            result.success(bytes)
                        } catch (e: Exception) {
                            result.error("PAGE_RENDER_ERROR", e.message, null)
                        }
                    }
                }
                "closePdf" -> {
                    synchronized(this) {
                        try {
                            currentPdfRenderer?.close()
                            currentPdfRenderer = null
                            currentPfd?.close()
                            currentPfd = null
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CLOSE_ERROR", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "إشعارات المنظومة الجامعية"
            val descriptionText = "تنبيهات المحاضرات والتبليغات الرسمية الفورية"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(NOTIF_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                enableLights(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 250, 150, 250)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        synchronized(this) {
            currentPdfRenderer?.close()
            currentPdfRenderer = null
            currentPfd?.close()
            currentPfd = null
        }
        super.onDestroy()
    }
}
