import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

enum MonthlyCardSaveResult { saved, cancelled, downloadStarted }

/// Uses the platform's save dialog; never uploads the private listening card.
abstract interface class MonthlyCardSaver {
  Future<MonthlyCardSaveResult> save(Uint8List png, String fileName);
}

class FilePickerMonthlyCardSaver implements MonthlyCardSaver {
  @override
  Future<MonthlyCardSaveResult> save(Uint8List png, String fileName) async {
    final result = await FilePicker.saveFile(
      dialogTitle: 'ذخیرهٔ کارت شنیداری',
      fileName: fileName,
      mimeType: 'image/png',
      bytes: png,
    );
    // The web plugin starts a browser download and cannot observe completion.
    if (kIsWeb) return MonthlyCardSaveResult.downloadStarted;
    return result == null
        ? MonthlyCardSaveResult.cancelled
        : MonthlyCardSaveResult.saved;
  }
}
