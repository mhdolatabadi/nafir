import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/journey/data/monthly_card_export.dart';

class SavePicker extends FilePickerPlatform {
  String? name;
  String? type;
  Uint8List? data;
  Uri? result;
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    name = fileName;
    type = mimeType;
    data = bytes;
    return result;
  }
}

void main() {
  test('save adapter passes PNG bytes and MIME type and preserves cancellation',
      () async {
    final previous = FilePickerPlatform.instance;
    final picker = SavePicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
    final saver = FilePickerMonthlyCardSaver();
    final png = Uint8List.fromList([137, 80, 78, 71]);
    expect(await saver.save(png, 'rhythmo-2026-10.png'),
        MonthlyCardSaveResult.cancelled);
    picker.result = Uri.parse('content://documents/card.png');
    expect(await saver.save(png, 'rhythmo-2026-10.png'),
        MonthlyCardSaveResult.saved);
    expect(picker.name, 'rhythmo-2026-10.png');
    expect(picker.type, 'image/png');
    expect(picker.data, same(png));
  });
}
