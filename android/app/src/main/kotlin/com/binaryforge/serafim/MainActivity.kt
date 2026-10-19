package com.binaryforge.serafim

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    /** The Dart call waiting for the system installer to finish. */
    private var pendingInstall: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createMessagesChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "versionInfo" -> result.success(versionInfo())
                    "freeBytes" -> result.success(cacheDir.usableSpace)
                    // CPU types this phone runs, best first (e.g. arm64-v8a,
                    // armeabi-v7a), to pick the matching APK.
                    "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "inspectApk" -> result.success(
                        inspectApk(call.argument<String>("path") ?: "")
                    )
                    "install" -> install(call.argument<String>("path") ?: "", result)
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun packageInfo(flags: Int = 0): PackageInfo =
        packageManager.getPackageInfo(packageName, flags)

    @Suppress("DEPRECATION")
    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    private fun versionInfo(): Map<String, Any?> {
        val info = packageInfo()
        return mapOf("versionName" to info.versionName, "versionCode" to versionCodeOf(info))
    }

    /** Whether the user has allowed Serafim to install apps (Android 8+). */
    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    /** The per-app "Install unknown apps" switch for Serafim. */
    private fun openInstallSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /**
     * Reads a downloaded APK without installing it: its package, version and
     * whether it is signed with the same key as this app. Lets Dart refuse an
     * APK the system would reject anyway, with a clear message.
     */
    @Suppress("DEPRECATION")
    private fun inspectApk(path: String): Map<String, Any?>? {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val archive = packageManager.getPackageArchiveInfo(path, flags) ?: return null
        val installed = packageInfo(flags)
        return mapOf(
            "packageName" to archive.packageName,
            "samePackage" to (archive.packageName == packageName),
            "versionCode" to versionCodeOf(archive),
            "versionName" to archive.versionName,
            "sameSigner" to (signerDigests(archive) == signerDigests(installed)),
        )
    }

    @Suppress("DEPRECATION")
    private fun signerDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        } ?: return emptySet()
        val sha = java.security.MessageDigest.getInstance("SHA-256")
        return signatures.map { sig ->
            sha.digest(sig.toByteArray()).joinToString("") { "%02x".format(it) }
        }.toSet()
    }

    /**
     * Hands the APK to the system installer through a FileProvider content
     * URI. Android always shows its own confirmation; the result says whether
     * the user installed, cancelled, or the install failed.
     */
    @Suppress("DEPRECATION")
    private fun install(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing", "The downloaded update is gone.", null)
            return
        }
        if (pendingInstall != null) {
            result.error("busy", "An install is already in progress.", null)
            return
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_RETURN_RESULT, true)
            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, false)
        }
        pendingInstall = result
        try {
            startActivityForResult(intent, INSTALL_REQUEST)
        } catch (e: Exception) {
            pendingInstall = null
            result.error("no_installer", "No app on this phone can install updates.", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == INSTALL_REQUEST) {
            val result = pendingInstall
            pendingInstall = null
            result?.success(
                when (resultCode) {
                    Activity.RESULT_OK -> "installed"
                    Activity.RESULT_CANCELED -> "cancelled"
                    else -> "failed"
                }
            )
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    /**
     * Push notifications are delivered by FCM while the app is closed, so the
     * channel they post to has to exist natively. High importance makes new
     * messages appear as heads-up banners with sound. (Android 8+.)
     */
    private fun createMessagesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            MESSAGES_CHANNEL_ID,
            "Messages",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "New messages from your conversations"
            enableVibration(true)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    companion object {
        // Must match the channel id the backend sends and the manifest default.
        const val MESSAGES_CHANNEL_ID = "messages"
        const val UPDATER_CHANNEL = "serafim/updater"
        private const val INSTALL_REQUEST = 4710
    }
}
