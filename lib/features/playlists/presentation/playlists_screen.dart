import 'package:flutter/material.dart';
import 'package:nafir/core/widgets/glass_surface.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/playlists/application/playlists_controller.dart';
import 'package:nafir/features/playlists/data/playlist.dart';
import 'package:nafir/features/playlists/presentation/popular_playlists_screen.dart';
import 'package:nafir/features/playlists/presentation/shared_playlist_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({
    super.key,
    required this.controller,
    required this.libraryTracks,
    required this.player,
  });

  final PlaylistsController controller;
  final List<Track> libraryTracks;
  final PlayerController player;

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  Future<void> _create() async {
    final name = await _askName(context, 'Playlist جدید');
    if (name == null) return;
    final playlist = await widget.controller.create(name);
    if (!mounted) return;
    if (playlist == null) {
      _message('ساخت Playlist ناموفق بود.');
      return;
    }
    _open(playlist);
  }

  Future<void> _open(Playlist playlist) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlaylistDetailScreen(
        playlistId: playlist.id,
        controller: widget.controller,
        libraryTracks: widget.libraryTracks,
        player: widget.player,
      ),
    ));
    widget.controller.load();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Opens a playlist someone shared, from a pasted link.
  Future<void> _openLink() async {
    final field = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('باز کردن لینک اشتراک'),
        content: TextField(
          controller: field,
          autofocus: true,
          textDirection: TextDirection.ltr,
          decoration:
              const InputDecoration(hintText: 'لینک Playlist را اینجا بچسبان'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('باز کن'),
          ),
        ],
      ),
    );
    field.dispose();
    if (input == null || !mounted) return;
    final token = shareTokenFrom(input);
    if (token == null) {
      _message('این لینک Playlist نفیر نیست.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SharedPlaylistScreen(
        shareToken: token,
        controller: widget.controller,
        player: widget.player,
      ),
    ));
  }

  Future<void> _openPopular() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PopularPlaylistsScreen(
        controller: widget.controller,
        player: widget.player,
      ),
    ));
    if (mounted) widget.controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlistها'),
        actions: [
          IconButton(
            tooltip: 'Playlistهای محبوب',
            onPressed: _openPopular,
            icon: const Icon(Icons.local_fire_department_outlined),
          ),
          IconButton(
            tooltip: 'باز کردن لینک اشتراک',
            onPressed: _openLink,
            icon: const Icon(Icons.add_link),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.playlist_add),
        label: const Text('Playlist جدید'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => switch (widget.controller.status) {
              PlaylistsStatus.loading =>
                const Center(child: CircularProgressIndicator()),
              PlaylistsStatus.error => _Retry(
                  onRetry: () async {
                    await widget.controller.load();
                  },
                ),
              PlaylistsStatus.loaded => widget.controller.playlists.isEmpty
                  ? const Center(child: Text('هنوز Playlistی نساخته‌ای.'))
                  : RefreshIndicator(
                      onRefresh: () async {
                        await widget.controller.load();
                      },
                      child: _PlaylistsOverview(
                        playlists: widget.controller.playlists,
                        onOpen: _open,
                      ),
                    ),
            },
          ),
        ),
      ),
    );
  }
}

class _PlaylistsOverview extends StatelessWidget {
  const _PlaylistsOverview({
    required this.playlists,
    required this.onOpen,
  });

  final List<Playlist> playlists;
  final void Function(Playlist playlist) onOpen;

  @override
  Widget build(BuildContext context) {
    final featured = playlists.take(3).toList(growable: false);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
      children: [
        if (featured.isNotEmpty) ...[
          SizedBox(
            height: 184,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featured.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final playlist = featured[index];
                return _PlaylistFeatureCard(
                  playlist: playlist,
                  onTap: () => onOpen(playlist),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(
            'همهٔ Playlistها',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        for (final playlist in playlists)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: _PlaylistCover(trackCount: playlist.trackCount, size: 56),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (playlist.shareToken != null)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 6),
                    child: Tooltip(
                      message: 'با لینک به اشتراک گذاشته شده',
                      child: Icon(Icons.link, size: 16),
                    ),
                  ),
              ],
            ),
            subtitle: Text('${playlist.trackCount} قطعه موسیقی'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => onOpen(playlist),
          ),
      ],
    );
  }
}

class _PlaylistFeatureCard extends StatelessWidget {
  const _PlaylistFeatureCard({
    required this.playlist,
    required this.onTap,
  });

  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PlaylistCover(trackCount: playlist.trackCount, size: 148),
            const SizedBox(height: 10),
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              '${playlist.trackCount} قطعه موسیقی',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.controller,
    required this.libraryTracks,
    required this.player,
  });

  final String playlistId;
  final PlaylistsController controller;
  final List<Track> libraryTracks;
  final PlayerController player;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  Playlist? playlist;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await widget.controller.loadPlaylist(widget.playlistId);
    if (!mounted) return;
    setState(() {
      playlist = loaded;
      busy = false;
    });
  }

  Future<void> _selectTracks() async {
    final current = playlist;
    if (current == null) return;
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _TrackPicker(
        tracks: widget.libraryTracks,
        selected: current.tracks.map((track) => track.id).toSet(),
      ),
    );
    if (selected == null) return;
    await _save(selected.toList());
  }

  Future<void> _save(List<String> ids) async {
    setState(() => busy = true);
    final saved = await widget.controller.replaceTracks(widget.playlistId, ids);
    if (!mounted) return;
    setState(() {
      playlist = saved;
      busy = false;
    });
    if (saved == null) _message('ذخیرهٔ Playlist ناموفق بود.');
  }

  Future<void> _share() async {
    final current = playlist;
    if (current == null) return;
    await showShareSheet(context,
        playlist: current, controller: widget.controller);
    if (mounted) await _load();
  }

  Future<void> _rename() async {
    final current = playlist;
    if (current == null) return;
    final name = await _askName(
      context,
      'تغییر نام Playlist',
      initialValue: current.name,
    );
    if (name == null) return;
    if (await widget.controller.rename(current.id, name)) {
      await _load();
    } else {
      _message('تغییر نام ناموفق بود.');
    }
  }

  Future<void> _delete() async {
    final current = playlist;
    if (current == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف Playlist؟'),
        content: const Text('آهنگ‌های کتابخانه حذف نمی‌شوند.'),
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
    final deleted = await widget.controller.delete(current.id);
    if (!mounted) return;
    if (deleted) {
      Navigator.pop(context);
    } else {
      _message('حذف Playlist ناموفق بود.');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final current = playlist;
    return Scaffold(
      appBar: AppBar(
        title: Text(current?.name ?? 'Playlist'),
        actions: [
          IconButton(
            tooltip: 'اشتراک‌گذاری',
            onPressed: current == null ? null : _share,
            icon: Icon(current?.shareToken == null ? Icons.share : Icons.link),
          ),
          IconButton(
            tooltip: 'تغییر نام',
            onPressed: current == null ? null : _rename,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'حذف',
            onPressed: current == null ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: current == null || busy ? null : _selectTracks,
        icon: const Icon(Icons.library_add_outlined),
        label: const Text('انتخاب آهنگ‌ها'),
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : current == null
              ? _Retry(onRetry: _load)
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: current.tracks.isEmpty
                        ? const Center(
                            child: Text('آهنگ‌های این Playlist را انتخاب کن.'),
                          )
                        : Column(
                            children: [
                              _PlaylistDetailHeader(
                                playlist: current,
                                onPlay: () =>
                                    widget.player.playFrom(current.tracks, 0),
                                onShuffle: () =>
                                    widget.player.playShuffled(current.tracks),
                              ),
                              Expanded(
                                child: ReorderableListView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 8, 8, 112),
                                  itemCount: current.tracks.length,
                                  onReorderItem: (oldIndex, newIndex) {
                                    final tracks =
                                        List<Track>.from(current.tracks);
                                    tracks.insert(
                                      newIndex,
                                      tracks.removeAt(oldIndex),
                                    );
                                    setState(() {
                                      playlist = Playlist(
                                        id: current.id,
                                        name: current.name,
                                        trackCount: tracks.length,
                                        tracks: tracks,
                                        createdAt: current.createdAt,
                                        updatedAt: current.updatedAt,
                                        shareToken: current.shareToken,
                                      );
                                    });
                                    _save(tracks
                                        .map((track) => track.id)
                                        .toList());
                                  },
                                  itemBuilder: (context, index) {
                                    final track = current.tracks[index];
                                    return ListTile(
                                      key: ValueKey(track.id),
                                      leading: const _PlaylistTrackHandle(),
                                      title: Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        track.artist?.trim().isNotEmpty == true
                                            ? track.artist!
                                            : 'خواننده نامشخص',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: const Icon(Icons.more_vert),
                                      onTap: () => widget.player
                                          .playFrom(current.tracks, index),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
    );
  }
}

class _PlaylistDetailHeader extends StatelessWidget {
  const _PlaylistDetailHeader({
    required this.playlist,
    required this.onPlay,
    required this.onShuffle,
  });

  final Playlist playlist;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: GlassSurface(
        blur: 12,
        radius: 24,
        shadow: false,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _PlaylistCover(trackCount: playlist.trackCount, size: 92),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${playlist.trackCount} قطعه موسیقی',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: playlist.tracks.isEmpty ? null : onPlay,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('پخش'),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'پخش تصادفی',
                        onPressed: playlist.tracks.isEmpty ? null : onShuffle,
                        icon: const Icon(Icons.shuffle_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.trackCount, required this.size});

  final int trackCount;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size > 100 ? 24 : 18),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [NafirGlass.primary, Color(0xFF4E3B8D)],
        ),
        boxShadow: [
          BoxShadow(
            color: NafirGlass.primary.withValues(alpha: 0.2),
            offset: const Offset(0, 10),
            blurRadius: 24,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            trackCount == 0 ? Icons.queue_music : Icons.library_music,
            size: size * 0.36,
            color: const Color(0xFFFFF5F5),
          ),
          PositionedDirectional(
            end: 10,
            bottom: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.66),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Text(
                  trackCount.toString(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistTrackHandle extends StatelessWidget {
  const _PlaylistTrackHandle();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 40,
      height: 40,
      child: Icon(Icons.drag_handle),
    );
  }
}

class _TrackPicker extends StatefulWidget {
  const _TrackPicker({required this.tracks, required this.selected});

  final List<Track> tracks;
  final Set<String> selected;

  @override
  State<_TrackPicker> createState() => _TrackPickerState();
}

class _TrackPickerState extends State<_TrackPicker> {
  late final Set<String> selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('انتخاب آهنگ‌ها'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: widget.tracks.isEmpty
            ? const Center(child: Text('کتابخانه خالی است.'))
            : ListView.builder(
                itemCount: widget.tracks.length,
                itemBuilder: (context, index) {
                  final track = widget.tracks[index];
                  return CheckboxListTile(
                    value: selected.contains(track.id),
                    title: Text(track.title),
                    subtitle: Text(track.artist ?? ''),
                    onChanged: (checked) {
                      setState(() {
                        if (checked ?? false) {
                          selected.add(track.id);
                        } else {
                          selected.remove(track.id);
                        }
                      });
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, selected),
          child: const Text('ذخیره'),
        ),
      ],
    );
  }
}

Future<String?> _askName(
  BuildContext context,
  String title, {
  String initialValue = '',
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 200,
        decoration: const InputDecoration(labelText: 'نام'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) Navigator.pop(context, name);
          },
          child: const Text('ذخیره'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('تلاش دوباره'),
        ),
      );
}
