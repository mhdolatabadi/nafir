import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/playlists/application/playlists_controller.dart';
import 'package:nafir/features/playlists/data/playlist.dart';

/// A playlist someone shared by link: its tracks can be played, not changed.
class SharedPlaylistScreen extends StatefulWidget {
  const SharedPlaylistScreen({
    super.key,
    required this.shareToken,
    required this.controller,
    required this.player,
    this.onSaved,
  });

  final String shareToken;
  final PlaylistsController controller;
  final PlayerController player;

  /// Called after the playlist was saved to the account, for example to
  /// reload the library the copied tracks now belong to.
  final VoidCallback? onSaved;

  @override
  State<SharedPlaylistScreen> createState() => _SharedPlaylistScreenState();
}

enum _Load { loading, loaded, unavailable, failed }

class _SharedPlaylistScreenState extends State<SharedPlaylistScreen> {
  _Load _state = _Load.loading;
  SharedPlaylist? _playlist;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final result = await widget.controller.saveShared(widget.shareToken);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result == SaveSharedResult.saved) widget.onSaved?.call();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(switch (result) {
        SaveSharedResult.saved =>
          'به Playlistها و کتابخانه‌ات اضافه شد. این نسخه مال خودت است.',
        SaveSharedResult.alreadyYours => 'این Playlist خودت است.',
        SaveSharedResult.noSpace =>
          'فضای کافی در حسابت نیست. چند آهنگ را حذف کن و دوباره امتحان کن.',
        SaveSharedResult.uploadsDisabled =>
          'افزودن آهنگ فعلاً غیرفعال است. کمی بعد دوباره امتحان کن.',
        SaveSharedResult.gone => 'این Playlist دیگر به اشتراک گذاشته نمی‌شود.',
        SaveSharedResult.failed => 'افزودن ناموفق بود. دوباره تلاش کن.',
      }),
    ));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _Load.loading);
    try {
      final playlist = await widget.controller.openShared(widget.shareToken);
      if (!mounted) return;
      setState(() {
        _playlist = playlist;
        _state = _Load.loaded;
      });
    } on SharedPlaylistUnavailable {
      if (mounted) setState(() => _state = _Load.unavailable);
    } catch (_) {
      if (mounted) setState(() => _state = _Load.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _playlist;
    return Scaffold(
      appBar: AppBar(title: Text(playlist?.name ?? 'Playlist اشتراکی')),
      body: switch (_state) {
        _Load.loading => const Center(child: CircularProgressIndicator()),
        _Load.unavailable => const _Message(
            icon: Icons.link_off,
            text: 'این لینک اشتباه است یا صاحبش اشتراک‌گذاری را لغو کرده است.',
          ),
        _Load.failed => _Message(
            icon: Icons.cloud_off,
            text: 'بارگذاری Playlist ناموفق بود.',
            action: FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش دوباره'),
            ),
          ),
        _Load.loaded => _Contents(
            playlist: playlist!,
            player: widget.player,
            saving: _saving,
            onSave: playlist.isOwner ? null : _save,
          ),
      },
    );
  }
}

class _Contents extends StatelessWidget {
  const _Contents({
    required this.playlist,
    required this.player,
    required this.saving,
    this.onSave,
  });

  final SharedPlaylist playlist;
  final PlayerController player;
  final bool saving;

  /// Saves a copy to the account; null for the owner's own playlist.
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final tracks = playlist.tracks;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(playlist.isOwner
                  ? 'Playlist خودت، که با لینک به اشتراک گذاشته‌ای'
                  : 'اشتراک‌گذاری‌شده توسط ${playlist.owner}'),
              subtitle: Text('${tracks.length} آهنگ'),
            ),
            if (tracks.isEmpty)
              const Expanded(
                child: _Message(
                  icon: Icons.music_off,
                  text: 'این Playlist فعلاً آهنگی ندارد.',
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => player.playFrom(tracks, 0),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('پخش همه'),
                    ),
                    if (onSave != null)
                      OutlinedButton.icon(
                        onPressed: saving ? null : onSave,
                        icon: saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.library_add),
                        label: const Text('افزودن به حساب من'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return ListTile(
                      leading: const Icon(Icons.music_note),
                      title: Text(track.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: track.artist == null
                          ? null
                          : Text(track.artist!,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => player.playFrom(tracks, index),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Lets the owner share a playlist by link, copy it, or stop sharing.
Future<void> showShareSheet(
  BuildContext context, {
  required Playlist playlist,
  required PlaylistsController controller,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ShareSheet(playlist: playlist, controller: controller),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.playlist, required this.controller});

  final Playlist playlist;
  final PlaylistsController controller;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late String? _token = widget.playlist.shareToken;
  bool _busy = false;
  String? _error;

  Future<void> _share() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final token = await widget.controller.share(widget.playlist.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _token = token ?? _token;
      if (token == null) _error = 'ساخت لینک ناموفق بود. دوباره تلاش کن.';
    });
  }

  Future<void> _unshare() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.controller.unshare(widget.playlist.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _token = null;
      } else {
        _error = 'لغو اشتراک ناموفق بود. دوباره تلاش کن.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final token = _token;
    final origin = AppConfiguration.apiBaseUri;
    final link = token == null
        ? null
        : origin == null
            ? token
            : sharedPlaylistLink(origin, token).toString();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('اشتراک‌گذاری «${widget.playlist.name}»',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              link == null
                  ? 'با لینک اشتراک، هر کسی که حساب نفیر دارد می‌تواند این Playlist را ببیند و آهنگ‌هایش را پخش کند. هر وقت بخواهی می‌توانی لینک را باطل کنی.'
                  : 'هر کسی که این لینک را دارد و وارد نفیر شده، این Playlist را می‌بیند و پخش می‌کند.',
            ),
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
                      const SnackBar(content: Text('لینک کپی شد.')));
                },
                icon: const Icon(Icons.copy),
                label: const Text('کپی لینک'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : _unshare,
                icon: const Icon(Icons.link_off),
                label: const Text('لغو اشتراک (لینک فعلی باطل می‌شود)'),
              ),
            ] else
              FilledButton.icon(
                onPressed: _busy ? null : _share,
                icon: const Icon(Icons.link),
                label: const Text('ساخت لینک اشتراک'),
              ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
