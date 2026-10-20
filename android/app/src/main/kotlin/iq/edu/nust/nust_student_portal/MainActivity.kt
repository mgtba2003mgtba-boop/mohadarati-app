package iq.edu.nust.nust_student_portal

import android.annotation.SuppressLint
import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsetsController
import android.webkit.*
import android.widget.FrameLayout
import android.widget.Toast

class MainActivity : Activity() {

    private lateinit var webView: WebView
    private var fileUploadCallback: ValueCallback<Array<Uri>>? = null
    private var pendingPermissionRequest: PermissionRequest? = null

    companion object {
        private const val APP_URL = "https://mohadarati.vercel.app"
        private const val FILE_CHOOSER_REQUEST_CODE = 2001
        private const val CAMERA_PERMISSION_REQUEST_CODE = 2002
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. تفعيل النمط الفاتح النظيف لشريط الحالة ليتطابق مع هوية التطبيق
        setupStatusBar()

        // 2. إنشاء حاوية كاملة للشاشة
        val rootLayout = FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.parseColor("#F8FAFC"))
        }

        // 3. تهيئة محرك الويب فائق السرعة
        webView = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.parseColor("#F8FAFC"))
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
        }

        configureWebSettings(webView.settings)
        setupWebClients()

        rootLayout.addView(webView)
        setContentView(rootLayout)

        // 4. تحميل المنظومة من السيرفر المباشر
        if (savedInstanceState != null) {
            webView.restoreState(savedInstanceState)
        } else {
            webView.loadUrl(APP_URL)
        }
    }

    private fun setupStatusBar() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.setSystemBarsAppearance(
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS,
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
            )
            window.statusBarColor = Color.parseColor("#FFFFFF")
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            window.statusBarColor = Color.parseColor("#FFFFFF")
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebSettings(settings: WebSettings) {
        settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
            mediaPlaybackRequiresUserGesture = false

            // تشغيل الكاش المحلي الذكي لتسريع فتح التطبيق
            cacheMode = WebSettings.LOAD_DEFAULT

            // دعم الاتصالات الآمنة المتكاملة
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW

            // إضافة وسم المنظومة لتمييز الغلاف الأصلي
            val defaultUa = userAgentString
            userAgentString = "$defaultUa MohadaratiApp/1.0.2 (Android Native Dynamic Shell)"
        }
    }

    private fun setupWebClients() {
        // إدارة صلاحيات الكاميرا واختيار الملفات للأساتذة والممثلين
        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest?) {
                if (request == null) return
                val requestedResources = request.resources
                val needsCamera = requestedResources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)

                if (needsCamera) {
                    if (checkSelfPermission(android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        request.grant(requestedResources)
                    } else {
                        pendingPermissionRequest = request
                        requestPermissions(
                            arrayOf(android.Manifest.permission.CAMERA),
                            CAMERA_PERMISSION_REQUEST_CODE
                        )
                    }
                } else {
                    request.grant(requestedResources)
                }
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                fileUploadCallback?.onReceiveValue(null)
                fileUploadCallback = filePathCallback

                val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    fileChooserParams?.acceptTypes?.let { types ->
                        val validTypes = types.filter { it.isNotBlank() }
                        if (validTypes.isNotEmpty()) {
                            putExtra(Intent.EXTRA_MIME_TYPES, validTypes.toTypedArray())
                        }
                    }
                }

                try {
                    startActivityForResult(
                        Intent.createChooser(intent, "اختر ملف المحاضرة"),
                        FILE_CHOOSER_REQUEST_CODE
                    )
                } catch (e: Exception) {
                    fileUploadCallback?.onReceiveValue(null)
                    fileUploadCallback = null
                    return false
                }
                return true
            }
        }

        // إدارة الروابط والتصفح الداخلي والخارجي
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url?.toString() ?: return false

                // إبقاء روابط التطبيق والسيرفر داخل الـ WebView
                if (url.startsWith(APP_URL) || url.startsWith("https://mohadarati.vercel.app") || url.startsWith("http://192.168.")) {
                    return false
                }

                // فتح الروابط الخارجية (تيليجرام، واتساب، روابط التنزيل الخارجية) في التطبيقات المناسبة
                return try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    startActivity(intent)
                    true
                } catch (e: Exception) {
                    false
                }
            }
        }

        // دعم تنزيل ملفات المحاضرات عبر مدير التنزيلات بالنظام
        webView.setDownloadListener { url, userAgent, contentDisposition, mimetype, _ ->
            try {
                val request = DownloadManager.Request(Uri.parse(url)).apply {
                    setMimeType(mimetype)
                    addRequestHeader("User-Agent", userAgent)
                    setDescription("تنزيل ملف المحاضرة...")
                    setTitle(URLUtil.guessFileName(url, contentDisposition, mimetype))
                    setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                    setDestinationInExternalPublicDir(
                        Environment.DIRECTORY_DOWNLOADS,
                        URLUtil.guessFileName(url, contentDisposition, mimetype)
                    )
                }
                val dm = getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
                dm?.enqueue(request)
            } catch (e: Exception) {
                // فتح في المتصفح الخارجي كحل بديل في حال تعذر مدير التنزيلات
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    startActivity(intent)
                } catch (ignored: Exception) {}
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == FILE_CHOOSER_REQUEST_CODE) {
            if (fileUploadCallback != null) {
                val results: Array<Uri>? = if (resultCode == RESULT_OK && data != null) {
                    val uri = data.data
                    if (uri != null) {
                        arrayOf(uri)
                    } else if (data.clipData != null) {
                        val clip = data.clipData!!
                        Array(clip.itemCount) { i -> clip.getItemAt(i).uri }
                    } else {
                        null
                    }
                } else {
                    null
                }
                fileUploadCallback?.onReceiveValue(results)
                fileUploadCallback = null
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                pendingPermissionRequest?.grant(pendingPermissionRequest?.resources)
            } else {
                pendingPermissionRequest?.deny()
            }
            pendingPermissionRequest = null
        }
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (this::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        if (this::webView.isInitialized) {
            webView.saveState(outState)
        }
    }

    override fun onDestroy() {
        if (this::webView.isInitialized) {
            webView.destroy()
        }
        super.onDestroy()
    }
}
