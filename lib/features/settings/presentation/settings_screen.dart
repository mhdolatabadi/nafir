import 'package:flutter/material.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/core/links/open_link.dart';
import 'package:nafir/core/links/site_page.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/core/format_size.dart';
import 'package:nafir/features/bots/application/bot_link_controller.dart';
import 'package:nafir/features/bots/presentation/bot_link_section.dart';
import 'package:nafir/features/library/application/library_controller.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/settings/presentation/crossfade_setting.dart';
import 'package:nafir/features/settings/application/cache_controller.dart';
import 'package:nafir/features/settings/presentation/delete_account_screen.dart';
import 'package:nafir/features/settings/presentation/storage_usage_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.cache,
    this.botLinks,
    this.library,
    this.player,
    this.email,
    this.onDeleteAccount,
    this.onSignOutEverywhere,
    this.siteUri = AppConfiguration.sitePage,
    this.openLink = openExternalLink,
  });

  /// The signed-in account; null hides the account section.
  final String? email;

  /// Deletes the account; null hides the option.
  final Future<void> Function(String password)? onDeleteAccount;

  /// Ends the account's sessions on every other device; null hides it.
  final Future<void> Function()? onSignOutEverywhere;

  /// Where a page of the Nafir site, such as `/privacy`, lives; null when
  /// there is no server.
  final SitePageResolver siteUri;

  final LinkOpener openLink;

  final CacheController cache;

  /// Reports the account's cloud storage use; null when there is none.
  final LibraryController? library;

  /// Playback preferences; null hides them.
  final PlayerController? player;

  /// Null when the app has no API to ask about bots.
  final BotLinkController? botLinks;

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

  Future<void> _signOutEverywhere(Future<void> Function() signOut) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('از همه‌ی دستگاه‌ها خارج شوی؟'),
        content: const Text(
          'روی همه‌ی گوشی‌ها و مرورگرهای دیگر از حسابت خارج می‌شوی و باید '
          'دوباره وارد شوی. این دستگاه وارد می‌ماند.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('خروج از بقیه'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var ok = true;
    try {
      await signOut();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'از همه‌ی دستگاه‌های دیگر خارج شدی.'
          : 'خروج از دستگاه‌های دیگر ناموفق بود. دوباره امتحان کن.'),
    ));
  }

  Future<void> _openPage(String path) => openSitePage(context, path,
      siteUri: widget.siteUri, openLink: widget.openLink);

  void _openDeleteAccount(String email, Future<void> Function(String) delete) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DeleteAccountScreen(
        email: email,
        onDelete: delete,
        onOpenPage: _openPage,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        // System navigation never covers the last item.
        padding: EdgeInsets.only(
          bottom: 24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (widget.library case final library?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ListenableBuilder(
                listenable: library,
                builder: (context, _) => StorageUsageCard(
                  usedBytes: library.usedBytes,
                  limitBytes: library.limitBytes,
                ),
              ),
            ),
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
                  leading: const Icon(NafirIcons.database),
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
              leading: Icon(NafirIcons.globe),
              title: Text('در نسخه‌ی وب، کش را خود مرورگر مدیریت می‌کند.'),
            ),
          if (widget.player case final player? when player.supportsCrossfade)
            CrossfadeSetting(player: player),
          if (widget.botLinks case final botLinks?)
            BotLinkSection(controller: botLinks),
          const Divider(),
          ListTile(
            title: const Text('حساب کاربری'),
            subtitle: widget.email == null
                ? null
                : Text(
                    widget.email!,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          ListTile(
            leading: const Icon(NafirIcons.shieldCheck),
            title: const Text('حریم خصوصی'),
            subtitle: const Text('چه چیزهایی نگه می‌داریم و چه کسی می‌بیند'),
            trailing: const Icon(NafirIcons.arrowSquareOut, size: 20),
            onTap: () => _openPage('/privacy'),
          ),
          if (widget.onSignOutEverywhere case final signOut?)
            ListTile(
              leading: const Icon(NafirIcons.signOut),
              title: const Text('خروج از همه‌ی دستگاه‌ها'),
              subtitle: const Text(
                'اگر گوشی یا رمزت دست کس دیگری افتاده، بقیه‌ی نشست‌ها را ببند',
              ),
              onTap: () => _signOutEverywhere(signOut),
            ),
          if ((widget.email, widget.onDeleteAccount)
              case (final String email, final delete?))
            ListTile(
              leading: Icon(NafirIcons.userCircleMinus, color: error),
              iconColor: error,
              textColor: error,
              title: const Text('حذف حساب کاربری'),
              subtitle: const Text(
                'حساب، موسیقی‌های ابری و فهرست‌های پخشت برای همیشه پاک می‌شوند',
              ),
              trailing: const Icon(NafirIcons.caretLeft, size: 20),
              onTap: () => _openDeleteAccount(email, delete),
            ),
        ],
      ),
    );
  }
}
