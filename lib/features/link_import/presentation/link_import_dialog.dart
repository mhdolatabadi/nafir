import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/features/link_import/application/link_import_controller.dart';
import 'package:nafir/features/link_import/data/link_import.dart';

/// Asks for a link to a song page or an audio file and starts importing
/// it. Returns the message to show once it is queued, or null if closed.
Future<String?> showLinkImportDialog(
  BuildContext context, {
  required LinkImportController controller,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _LinkImportDialog(controller: controller),
    );

class _LinkImportDialog extends StatefulWidget {
  const _LinkImportDialog({required this.controller});

  final LinkImportController controller;

  @override
  State<_LinkImportDialog> createState() => _LinkImportDialogState();
}

class _LinkImportDialogState extends State<_LinkImportDialog> {
  final _field = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _field.text = text;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final url = _field.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'لینک صفحه‌ی آهنگ یا فایل را بچسبان.');
      return;
    }
    setState(() => _error = null);
    final result = await widget.controller.submit(url);
    if (!mounted) return;
    if (result.queued) {
      Navigator.pop(context, result.message);
    } else {
      setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final busy = widget.controller.submitting;
        return AlertDialog(
          title: const Text('افزودن از لینک'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'لینک صفحه‌ی آهنگ در سایت موسیقی، یا لینک مستقیم فایل را بچسبان. نفیر بهترین کیفیت را پیدا می‌کند و به کتابخانه‌ات اضافه می‌کند.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _field,
                  autofocus: true,
                  enabled: !busy,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'لینک',
                    hintText: 'https://',
                    hintTextDirection: TextDirection.ltr,
                    errorText: _error,
                    errorMaxLines: 3,
                    suffixIcon: IconButton(
                      tooltip: 'چسباندن',
                      onPressed: busy ? null : _paste,
                      icon: const Icon(NafirIcons.copy),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
            FilledButton.icon(
              onPressed: busy ? null : _submit,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(NafirIcons.link),
              label: Text(busy ? 'در حال بررسی…' : 'افزودن'),
            ),
          ],
        );
      },
    );
  }
}

/// Says which of this session's link imports failed, and why.
class LinkImportFailures extends StatelessWidget {
  const LinkImportFailures({super.key, required this.controller});

  final LinkImportController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final failures = controller.failures;
        if (failures.isEmpty) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Card(
            color: scheme.errorContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(NafirIcons.warningCircle, color: scheme.error),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('افزودن از لینک ناموفق بود'),
                      ),
                      IconButton(
                        tooltip: 'بستن',
                        onPressed: controller.dismissFailures,
                        icon: const Icon(NafirIcons.x),
                      ),
                    ],
                  ),
                  for (final job in failures)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      child: Text(
                        '«${job.fileName}»${job.site.isEmpty ? '' : ' از ${job.site}'}: ${linkImportMessage(job.error)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
