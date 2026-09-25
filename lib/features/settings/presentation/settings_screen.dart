import 'package:flutter/material.dart';
import 'package:nafir/core/format_size.dart';
import 'package:nafir/features/settings/application/cache_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.cache});

  final CacheController cache;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.cache.isManaged) widget.cache.refresh();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('کش پاک شود؟'),
        content: const Text(
          'موسیقی‌های کتابخانه‌ات در فضای ابری می‌مانند و دفعه‌ی بعد دوباره '
          'از اینترنت پخش می‌شوند.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('پاک کن'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await widget.cache.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'کش پاک شد.' : 'پاک کردن کش ناموفق بود.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('کش موسیقی'),
            subtitle: Text(
              'آهنگ‌هایی که پخش کرده‌ای روی همین دستگاه نگه داشته می‌شوند تا '
              'دفعه‌ی بعد سریع‌تر و بدون اینترنت پخش شوند.',
            ),
          ),
          if (widget.cache.isManaged)
            ListenableBuilder(
              listenable: widget.cache,
              builder: (context, _) {
                final cache = widget.cache;
                final size = cache.sizeBytes;
                return ListTile(
                  leading: const Icon(Icons.storage),
                  title: Text(switch ((size, cache.failed)) {
                    (_, true) => 'حجم کش معلوم نشد',
                    (null, _) => 'در حال محاسبه…',
                    (final int bytes, _) => 'حجم کش: ${formatSize(bytes)}',
                  }),
                  trailing: OutlinedButton(
                    onPressed: cache.busy || size == 0 ? null : _clear,
                    child: const Text('پاک کردن کش'),
                  ),
                );
              },
            )
          else
            const ListTile(
              leading: Icon(Icons.public),
              title: Text('در نسخه‌ی وب، کش را خود مرورگر مدیریت می‌کند.'),
            ),
        ],
      ),
    );
  }
}
