import 'package:flutter/material.dart';
import 'package:nafir/features/upload/application/upload_controller.dart';
import 'package:nafir/features/upload/data/audio_picker.dart';
import 'package:nafir/features/upload/presentation/upload_status_card.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.email,
    required this.onLogout,
    required this.uploads,
    required this.picker,
  });

  final String email;
  final VoidCallback onLogout;
  final UploadController uploads;
  final AudioPicker picker;

  Future<void> _pickAndUpload() async {
    final file = await picker.pick(onReading: uploads.readingFile);
    if (file == null) return uploads.pickCancelled();
    await uploads.upload(file);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nafir موسیقی'),
        actions: [
          IconButton(
            tooltip: 'خروج ($email)',
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: uploads,
        builder: (context, _) => FloatingActionButton.extended(
          onPressed: uploads.isBusy ? null : _pickAndUpload,
          icon: const Icon(Icons.add),
          label: const Text('افزودن موسیقی'),
        ),
      ),
      body: Column(
        children: [
          UploadStatusCard(controller: uploads),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_queue_outlined, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'کتابخانهٔ شما خالی است',
                      style: TextStyle(fontSize: 20),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'با «افزودن موسیقی» فایل‌هایت را آپلود کن.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
