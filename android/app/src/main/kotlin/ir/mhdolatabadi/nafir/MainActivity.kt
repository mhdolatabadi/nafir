package ir.mhdolatabadi.nafir

import android.Manifest
import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Shares the Flutter engine with audio_service's background playback service,
// so music keeps playing and responds to media controls with the app closed.
class MainActivity : AudioServiceActivity() {
    private val channelName = "ir.mhdolatabadi.nafir/local_audio"
    private val permissionRequest = 4102
    private val writePermissionRequest = 4103
    private val deleteRequest = 4104
    private var pendingResult: MethodChannel.Result? = null

    /// Waiting for the storage write permission (Android 9 and older).
    private var pendingWrite: ((Boolean) -> Unit)? = null

    /// Waiting for the user to confirm deleting a file another app made.
    private var pendingDelete: ((Boolean) -> Unit)? = null

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
                "deleteAudio" -> handleDeleteAudio(call.argument<String>("uri"), result)
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
            val output = File.createTempFile("nafir-upload-", "-$safeName", cacheDir)
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

    /// Deletes a device track. Files Nafir saved are deleted directly; for
    /// others Android asks the user to confirm. Answers true once deleted and
    /// false when the user declined.
    private fun handleDeleteAudio(uri: String?, result: MethodChannel.Result) {
        if (uri == null) {
            result.error("INVALID_ARGUMENT", "Audio uri is required.", null)
            return
        }
        if (pendingDelete != null || pendingWrite != null) {
            result.error("BUSY", "Another storage request is active.", null)
            return
        }
        withWritePermission { granted ->
            if (!granted) {
                result.error("PERMISSION_DENIED", "Storage access was denied.", null)
                return@withWritePermission
            }
            deleteAudio(Uri.parse(uri), result, askUser = true)
        }
    }

    private fun deleteAudio(uri: Uri, result: MethodChannel.Result, askUser: Boolean) {
        try {
            contentResolver.delete(uri, null, null)
            result.success(true)
        } catch (error: SecurityException) {
            val sender = when {
                !askUser -> null
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                    MediaStore.createDeleteRequest(contentResolver, listOf(uri)).intentSender
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                    error is RecoverableSecurityException ->
                    error.userAction.actionIntent.intentSender
                else -> null
            }
            if (sender == null) {
                result.error("PERMISSION_DENIED", error.message, null)
                return
            }
            pendingDelete = { confirmed ->
                when {
                    !confirmed -> result.success(false)
                    // Android 11+ deletes the file itself once confirmed.
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> result.success(true)
                    else -> deleteAudio(uri, result, askUser = false)
                }
            }
            startIntentSenderForResult(sender, deleteRequest, null, 0, 0, 0)
        } catch (error: Exception) {
            result.error("DELETE_FAILED", error.message, null)
        }
    }

    @Deprecated("Needed for MediaStore delete confirmation on API 29+.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != deleteRequest) return
        val callback = pendingDelete ?: return
        pendingDelete = null
        callback(resultCode == Activity.RESULT_OK)
    }

    /// Android 9 and older need a runtime permission to change shared
    /// storage; newer versions use MediaStore and need none.
    private fun withWritePermission(callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            callback(true)
            return
        }
        pendingWrite = callback
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            writePermissionRequest,
        )
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
        if (requestCode == writePermissionRequest) {
            val callback = pendingWrite ?: return
            pendingWrite = null
            callback(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            return
        }
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
