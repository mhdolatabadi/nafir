import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:nafir/features/upload/data/audio_formats.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

abstract interface class AudioPicker {
  /// Returns null when the user cancels. [onReading] fires once a file was
  /// chosen and the platform starts copying it, which can take a while.
  Future<PickedAudio?> pick({void Function()? onReading});
}

class FilePickerAudioPicker implements AudioPicker {
  @override
  Future<PickedAudio?> pick({void Function()? onReading}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: audioContentTypes.keys.toList(),
      // Stream the file instead of loading it into memory.
      withReadStream: true,
      onFileLoading: (status) {
        if (status == FilePickerStatus.picking) onReading?.call();
      },
    );
    final file = result?.files.single;
    final stream = file?.readStream;
    if (file == null || stream == null) return null;
    var used = false;
    return PickedAudio(
      name: file.name,
      sizeBytes: file.size,
      openRead: () {
        // The picker's stream can only be listened to once.
        if (used) throw StateError('The picked file was already read.');
        used = true;
        return stream;
      },
      release: _clearPickerCache,
    );
  }

  /// Android copies picked files into the app cache; delete that copy so
  /// the upload never leaves a second permanent file on the device.
  static Future<void> _clearPickerCache() async {
    if (kIsWeb) return;
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {
      // Desktop platforms have nothing to clear.
    }
  }
}
