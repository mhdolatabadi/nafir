import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/features/playlists/application/playlists_controller.dart';
import 'package:nafir/features/playlists/data/playlist.dart';

/// Lets the owner invite people to add their own tracks to [playlist], and
/// manage who has joined.
Future<void> showCollabSheet(
  BuildContext context, {
  required Playlist playlist,
  required PlaylistsController controller,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _CollabSheet(playlist: playlist, controller: controller),
  );
}

class _CollabSheet extends StatefulWidget {
  const _CollabSheet({required this.playlist, required this.controller});

  final Playlist playlist;
  final PlaylistsController controller;

  @override
  State<_CollabSheet> createState() => _CollabSheetState();
}

class _CollabSheetState extends State<_CollabSheet> {
  late String? _token = widget.playlist.collabToken;
  late List<PlaylistMember> _members = widget.playlist.members;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<bool> Function() action, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = failure;
    });
  }

  Future<void> _newLink() => _run(() async {
        final token =
            await widget.controller.createCollabLink(widget.playlist.id);
        if (token != null) _token = token;
        return token != null;
      }, 'ساخت لینک دعوت ناموفق بود. دوباره تلاش کن.');

  Future<void> _revoke() => _run(() async {
        final ok = await widget.controller.revokeCollabLink(widget.playlist.id);
        if (ok) _token = null;
        return ok;
      }, 'باطل کردن لینک ناموفق بود. دوباره تلاش کن.');

  Future<void> _remove(PlaylistMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف عضو؟'),
        content: Text(
            '${member.name} از این Playlist حذف می‌شود و آهنگ‌هایی که اضافه کرده هم از آن بیرون می‌روند.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      final ok =
          await widget.controller.removeMember(widget.playlist.id, member.id);
      if (ok) {
        _members = [
          for (final m in _members)
            if (m.id != member.id) m
        ];
      }
      return ok;
    }, 'حذف عضو ناموفق بود. دوباره تلاش کن.');
  }

  @override
  Widget build(BuildContext context) {
    final token = _token;
    final origin = AppConfiguration.apiBaseUri;
    final link = token == null
        ? null
        : origin == null
            ? token
            : collabPlaylistLink(origin, token).toString();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'همکاری در «${widget.playlist.name}»',
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            const Text(
                'هر کسی که لینک دعوت را باز کند عضو می‌شود و از کتابخانه‌ی خودش آهنگ اضافه می‌کند. هر آهنگ از فضای کسی کم می‌شود که اضافه‌اش کرده.'),
            const SizedBox(height: 16),
            if (link != null) ...[
              Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(link, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('لینک دعوت کپی شد.')));
                },
                icon: const Icon(Icons.copy),
                label: const Text('کپی لینک دعوت'),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : _newLink,
                    icon: const Icon(Icons.refresh),
                    label: const Text('لینک تازه'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _revoke,
                    icon: const Icon(Icons.link_off),
                    label: const Text('باطل کردن لینک'),
                  ),
                ],
              ),
              Text(
                  'با لینک تازه یا باطل کردن، لینک قبلی دیگر کار نمی‌کند؛ اعضا می‌مانند.',
                  style: muted,
                  textAlign: TextAlign.center),
            ] else
              FilledButton.icon(
                onPressed: _busy ? null : _newLink,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('ساخت لینک دعوت'),
              ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 20),
            Text('اعضا (${_members.length})',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (_members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('هنوز کسی عضو نشده.', style: muted),
              )
            else
              for (final member in _members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                  ),
                  trailing: IconButton(
                    tooltip: 'حذف عضو',
                    onPressed: _busy ? null : () => _remove(member),
                    icon: const Icon(Icons.person_remove_outlined),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
