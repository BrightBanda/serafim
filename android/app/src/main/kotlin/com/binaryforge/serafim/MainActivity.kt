package com.example.serafim

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createMessagesChannel()
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
    }
}
