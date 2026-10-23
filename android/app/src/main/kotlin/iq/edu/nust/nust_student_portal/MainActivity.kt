package iq.edu.nust.nust_student_portal

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL_UPDATER = "iq.edu.nust.mohadarati/updater"
    private val CHANNEL_NOTIFICATIONS = "iq.edu.nust.mohadarati/notifications"
    private val NOTIF_CHANNEL_ID = "nust_live_notifications_v1"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

        // 1. قناة التحديثات وتثبيت الـ APK
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
}
