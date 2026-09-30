package ir.mhdolatabadi.nafir

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Shares the Flutter engine with audio_service's background playback service,
// so music keeps playing and responds to media controls with the app closed.
class MainActivity : AudioServiceActivity() {
    private val channelName = "ir.mhdolatabadi.nafir/local_audio"
    private val permissionRequest = 4102
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "queryAudio" -> handleQueryAudio(result)
                "copyAudioToCache" -> handleCopyAudioToCache(
                    call.argument<String>("uri"),
                    call.argument<String>("fileName"),
                    result,
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun handleQueryAudio(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(queryAudio())
        } else if (pendingResult != null) {
            result.error("BUSY", "An audio permission request is already active.", null)
        } else {
            pendingResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(audioPermission()),
                permissionRequest,
            )
        }
    }

    private fun handleCopyAudioToCache(
        uri: String?,
        fileName: String?,
        result: MethodChannel.Result,
    ) {
        if (uri == null || fileName == null) {
            result.error("INVALID_ARGUMENT", "Audio uri and filename are required.", null)
            return
        }
        if (!hasAudioPermission()) {
            result.error("PERMISSION_DENIED", "Audio access was denied.", null)
            return
        }
        try {
            val safeName = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val output = kotlin.io.path.createTempFile(
                cacheDir.toPath(),
                "nafir-upload-",
                "-$safeName",
            ).toFile()
            contentResolver.openInputStream(Uri.parse(uri)).use { input ->
                if (input == null) {
                    result.error("NOT_FOUND", "Audio file could not be opened.", null)
                    return
                }
                output.outputStream().use { outputStream -> input.copyTo(outputStream) }
            }
            result.success(output.absolutePath)
        } catch (error: Exception) {
            result.error("READ_FAILED", error.message, null)
        }
    }

    private fun audioPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    private fun hasAudioPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            ContextCompat.checkSelfPermission(this, audioPermission()) ==
            PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequest) return
        val result = pendingResult ?: return
        pendingResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            result.success(queryAudio())
        } else {
            result.error("PERMISSION_DENIED", "Audio access was denied.", null)
        }
    }

    private fun queryAudio(): List<Map<String, Any?>> {
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.SIZE,
        )
        val tracks = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val typeColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                tracks += mapOf(
                    "id" to id.toString(),
                    "title" to (cursor.getString(titleColumn)
                        ?: cursor.getString(nameColumn)
                        ?: "Unknown"),
                    "artist" to cursor.getString(artistColumn),
                    "album" to cursor.getString(albumColumn),
                    "contentType" to (cursor.getString(typeColumn) ?: "audio/*"),
                    "sizeBytes" to cursor.getLong(sizeColumn),
                    "fileName" to cursor.getString(nameColumn),
                    "uri" to ContentUris.withAppendedId(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        id,
                    ).toString(),
                )
            }
        }
        return tracks
    }
}
