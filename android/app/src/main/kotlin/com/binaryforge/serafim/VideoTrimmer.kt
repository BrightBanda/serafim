package com.binaryforge.serafim

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Cuts the part of a video that was chosen to send, to a new file, exact to
 * the frame. Media3's Transformer does the work (re-encoding on the phone's
 * hardware encoder), so nothing is added to the app but that library.
 *
 * Must be called on the main thread: the Transformer reports back on the
 * thread it was started from.
 */
@OptIn(UnstableApi::class)
class VideoTrimmer(private val context: Context) {
    private var running: Transformer? = null

    fun trim(path: String, startMs: Long, endMs: Long, result: MethodChannel.Result) {
        if (running != null) {
            result.error("busy", "Another video is being trimmed.", null)
            return
        }
        val source = File(path)
        if (!source.exists()) {
            result.error("missing", "That video isn't on your phone any more.", null)
            return
        }
        if (startMs < 0 || endMs <= startMs) {
            result.error("range", "Choose a part of the video to keep.", null)
            return
        }

        val dir = File(context.cacheDir, "trimmed").apply { mkdirs() }
        val out = File(dir, "trim-${System.currentTimeMillis()}.mp4")

        val clip = MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(startMs)
            .setEndPositionMs(endMs)
            .build()
        val item = MediaItem.Builder()
            .setUri(Uri.fromFile(source))
            .setClippingConfiguration(clip)
            .build()

        val transformer = Transformer.Builder(context)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    running = null
                    result.success(out.absolutePath)
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    running = null
                    out.delete()
                    result.error("failed", "Couldn't trim that video.", exportException.message)
                }
            })
            .build()
        running = transformer
        transformer.start(EditedMediaItem.Builder(item).build(), out.absolutePath)
    }

    /** Stops a trim in progress; its call then ends with a "cancelled" error. */
    fun cancel() {
        running?.cancel()
        running = null
    }
}
