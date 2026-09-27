import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:nafir/features/upload/data/audio_formats.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

abstract interface class AudioPicker {
  /// Returns null when the user cancels. [onReading] fires once a file was
  /// chosen and the platform starts copying it, which can take a while.
  Future<PickedAudio?> pick({void Function()? onReading});
}

/// Adds batch selection without breaking lightweight picker implementations
/// used by tests and integrations that only support one file.
extension AudioPickerBatch on AudioPicker {
  Future<List<PickedAudio>?> pickMany({void Function()? onReading}) async {
    if (this is FilePickerAudioPicker) {
      return (this as FilePickerAudioPicker).pickMultiple(
        onReading: onReading,
      );
    }
    final file = await pick(onReading: onReading);
    return file == null ? null : [file];
  }
}

class FilePickerAudioPicker implements AudioPicker {
  @override
  Future<PickedAudio?> pick({void Function()? onReading}) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: audioContentTypes.keys.toList(),
      onFileLoading: (status) {
        if (status == FilePickerStatus.picking) onReading?.call();
      },
    );
    if (file == null) return null;
    return (await _toPickedAudio([file])).single;
  }

  Future<List<PickedAudio>?> pickMultiple({
    void Function()? onReading,
  }) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: audioContentTypes.keys.toList(),
      onFileLoading: (status) {
        if (status == FilePickerStatus.picking) onReading?.call();
      },
    );
    if (files.isEmpty) return null;
    return _toPickedAudio(files);
  }

  Future<List<PickedAudio>> _toPickedAudio(
    List<PlatformFile> files,
  ) async {
    final picked = <PickedAudio>[];
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final sizeBytes = await file.length();
      if (sizeBytes == null) {
        await _clearPickerCache();
        throw StateError('The picked file size is unavailable.');
      }
      var used = false;
      picked.add(
        PickedAudio(
          name: file.name,
          sizeBytes: sizeBytes,
          openRead: () {
            // Each picker stream can only be listened to once.
            if (used) throw StateError('The picked file was already read.');
            used = true;
            return file.xFile.openRead();
          },
          // Clearing after the final sequential upload also releases the
          // temporary copies of every file in this picker batch.
          release: index == files.length - 1 ? _clearPickerCache : null,
        ),
      );
    }
    return picked;
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
