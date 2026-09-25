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
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: audioContentTypes.keys.toList(),
      onFileLoading: (status) {
        if (status == FilePickerStatus.picking) onReading?.call();
      },
    );
    if (result.isEmpty) return null;
    final file = result.single;
    final sizeBytes = await file.length();
    if (sizeBytes == null) {
      throw StateError('The picked file size is unavailable.');
    }
    var used = false;
    return PickedAudio(
      name: file.name,
      sizeBytes: sizeBytes,
      openRead: () {
        // The picker's stream can only be listened to once.
        if (used) throw StateError('The picked file was already read.');
        used = true;
        return file.xFile.openRead();
      },
      release: _clearPickerCache,
    );
  }

  /// Android copies picked files into the app cache; delete that copy so
  /// the upload never leaves a second permanent file on the device.
  static Future<void> _clearPickerCache() async {
    if (kIsWeb) return;
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {
      // Desktop platforms have nothing to clear.
    }
  }
}
