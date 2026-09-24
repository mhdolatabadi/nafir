import 'package:flutter/material.dart';
import 'package:nafir/features/upload/application/upload_controller.dart';

/// Shows the current upload's progress, result or failure.
class UploadStatusCard extends StatelessWidget {
  const UploadStatusCard({super.key, required this.controller});

  final UploadController controller;

  static String errorMessage(UploadError error) => switch (error) {
        UploadError.unsupportedFormat =>
          'این قالب پشتیبانی نمی‌شود. MP3، M4A، AAC، FLAC، OGG، OPUS، WAV یا WEBM انتخاب کن.',
        UploadError.tooLarge => 'حجم فایل بیشتر از ۲۰۰ مگابایت است.',
        UploadError.emptyFile => 'فایل خالی است.',
        UploadError.invalidAudio => 'این فایل، فایل صوتی معتبری نیست.',
        UploadError.network =>
          'ارسال فایل ناموفق بود. اتصال را بررسی کن و دوباره تلاش کن.',
        UploadError.unknown => 'آپلود ناموفق بود. دوباره تلاش کن.',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final name = controller.fileName ?? '';
        final (String label, double? progress, bool closable) =
            switch (controller.phase) {
          UploadPhase.idle => ('', null, false),
          UploadPhase.preparing => ('آماده‌سازی «$name»…', null, false),
          UploadPhase.uploading => (
              'در حال آپلود «$name» — ${(controller.progress * 100).round()}٪',
              controller.progress,
              false,
            ),
          UploadPhase.verifying => ('در حال بررسی «$name»…', null, false),
          UploadPhase.done => (
              '«${controller.uploaded?.title ?? name}» به کتابخانه اضافه شد.',
              1.0,
              true,
            ),
          UploadPhase.failed => (errorMessage(controller.error!), 0.0, true),
        };
        if (controller.phase == UploadPhase.idle) {
          return const SizedBox.shrink();
        }
        final failed = controller.phase == UploadPhase.failed;
        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      failed
                          ? Icons.error_outline
                          : controller.phase == UploadPhase.done
                              ? Icons.check_circle_outline
                              : Icons.upload_file,
                      color:
                          failed ? Theme.of(context).colorScheme.error : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label)),
                    if (closable)
                      IconButton(
                        tooltip: 'بستن',
                        onPressed: controller.dismiss,
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                if (!closable) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: progress),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
