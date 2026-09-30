import 'package:flutter/material.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/player/presentation/mini_player.dart';
import 'package:nafir/features/playlists/application/playlists_controller.dart';
import 'package:nafir/features/playlists/data/playlist.dart';
import 'package:nafir/features/playlists/presentation/shared_playlist_screen.dart';

/// Playlists their owners made public, most liked first. Link-only
/// playlists are never listed here.
class PopularPlaylistsScreen extends StatefulWidget {
  const PopularPlaylistsScreen({
    super.key,
    required this.controller,
    required this.player,
    this.onSaved,
  });

  final PlaylistsController controller;
  final PlayerController player;

  /// Passed on to a playlist opened from here, for when it is saved.
  final VoidCallback? onSaved;

  @override
  State<PopularPlaylistsScreen> createState() => _PopularPlaylistsScreenState();
}

class _PopularPlaylistsScreenState extends State<PopularPlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.loadPopular();
  }

  Future<void> _open(PublicPlaylist playlist) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SharedPlaylistScreen(
        shareToken: playlist.shareToken,
        controller: widget.controller,
        player: widget.player,
        onSaved: widget.onSaved,
      ),
    ));
    if (mounted) await widget.controller.loadPopular();
  }

  Future<void> _like(PublicPlaylist playlist) async {
    final result =
        await widget.controller.setLike(playlist.shareToken, playlist.likes);
    if (!mounted || result == LikeResult.done) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result == LikeResult.gone
          ? 'این Playlist دیگر عمومی نیست.'
          : 'پسندیدن ثبت نشد. دوباره تلاش کن.'),
    ));
    if (result == LikeResult.gone) await widget.controller.loadPopular();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Playlistهای محبوب')),
      bottomNavigationBar: MiniPlayer(player: widget.player),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final popular = controller.popular;
              return switch (controller.popularStatus) {
                PlaylistsStatus.loading when popular.isEmpty =>
                  const Center(child: CircularProgressIndicator()),
                PlaylistsStatus.error when popular.isEmpty => _Notice(
                    icon: Icons.cloud_off,
                    text: 'فهرست Playlistهای محبوب بارگذاری نشد.',
                    action: FilledButton.icon(
                      onPressed: controller.loadPopular,
                      icon: const Icon(Icons.refresh),
                      label: const Text('تلاش دوباره'),
                    ),
                  ),
                _ when popular.isEmpty => const _Notice(
                    icon: Icons.public,
                    text: 'هنوز Playlist عمومی‌ای نیست. وقتی Playlistی را '
                        'به اشتراک می‌گذاری، «عمومی» را انتخاب کن تا اینجا '
                        'نشان داده شود.',
                  ),
                _ => RefreshIndicator(
                    onRefresh: controller.loadPopular,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      // Room for the mini player and system insets below.
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      itemCount: popular.length,
                      itemBuilder: (context, index) {
                        final playlist = popular[index];
                        return _PopularRow(
                          playlist: playlist,
                          onOpen: () => _open(playlist),
                          onLike: controller.isLiking(playlist.shareToken)
                              ? null
                              : () => _like(playlist),
                        );
                      },
                    ),
                  ),
              };
            },
          ),
        ),
      ),
    );
  }
}

class _PopularRow extends StatelessWidget {
  const _PopularRow({
    required this.playlist,
    required this.onOpen,
    required this.onLike,
  });

  final PublicPlaylist playlist;
  final VoidCallback onOpen;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 8, end: 0),
      minTileHeight: 72,
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: const Icon(Icons.queue_music),
      ),
      title: Text(
        playlist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          playlist.isOwner ? 'Playlist خودت' : playlist.owner,
          '${playlist.trackCount} آهنگ',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PlaylistLikeButton(
        likes: playlist.likes,
        onPressed: onLike,
        compact: true,
      ),
      onTap: onOpen,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});

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
