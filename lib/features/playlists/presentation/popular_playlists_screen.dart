import 'package:flutter/material.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/core/widgets/glass_surface.dart';
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
      extendBody: true,
      appBar: AppBar(title: const Text('Playlistهای محبوب')),
      bottomNavigationBar: MiniPlayer(player: widget.player),
      body: NafirBackdrop(
        child: Center(
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
                      icon: NafirIcons.cloudSlash,
                      text: 'فهرست Playlistهای محبوب بارگذاری نشد.',
                      action: FilledButton.icon(
                        onPressed: controller.loadPopular,
                        icon: const Icon(NafirIcons.arrowsClockwise),
                        label: const Text('تلاش دوباره'),
                      ),
                    ),
                  _ when popular.isEmpty => const _Notice(
                      icon: NafirIcons.globe,
                      text: 'هنوز Playlist عمومی‌ای نیست. وقتی Playlistی را '
                          'به اشتراک می‌گذاری، «عمومی» را انتخاب کن تا اینجا '
                          'نشان داده شود.',
                    ),
                  _ => RefreshIndicator(
                      onRefresh: controller.loadPopular,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        // Room for the mini player and system insets below.
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 104),
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
    final text = Theme.of(context).textTheme;
    return GlassSurface(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: EdgeInsets.zero,
      blur: 16,
      radius: 22,
      tint: scheme.secondary,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      scheme.primary.withValues(alpha: 0.9),
                      scheme.secondary.withValues(alpha: 0.72),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.22),
                      offset: const Offset(0, 10),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: const Icon(NafirIcons.playlist),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        playlist.isOwner ? 'Playlist خودت' : playlist.owner,
                        '${playlist.trackCount} آهنگ',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PlaylistLikeButton(
                likes: playlist.likes,
                onPressed: onLike,
                compact: true,
              ),
            ],
          ),
        ),
      ),
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
