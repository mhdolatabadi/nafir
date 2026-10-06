import 'package:nafir/core/persian_digits.dart';
import 'package:flutter/material.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/core/links/open_link.dart';
import 'package:nafir/core/links/site_page.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/core/widgets/glass_surface.dart';
import 'package:nafir/features/auth/presentation/sign_in_prompt.dart';
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
    this.onSignIn,
    this.openShareToken,
    this.siteUri = AppConfiguration.sitePage,
    this.openLink = openExternalLink,
  });

  final PlaylistsController controller;
  final PlayerController player;

  /// Passed on to a playlist opened from here, for when it is saved.
  final VoidCallback? onSaved;

  /// Set when this is a guest's home: the app bar offers sign-in, and a
  /// guest who tries to like is asked to sign in.
  final VoidCallback? onSignIn;

  /// A shared playlist link the app was opened with, shown on top at once.
  final String? openShareToken;

  /// Where the guest's privacy policy link points.
  final SitePageResolver siteUri;

  final LinkOpener openLink;

  @override
  State<PopularPlaylistsScreen> createState() => _PopularPlaylistsScreenState();
}

class _PopularPlaylistsScreenState extends State<PopularPlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.loadPopular();
    final shareToken = widget.openShareToken;
    if (shareToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openToken(shareToken);
      });
    }
  }

  Future<void> _open(PublicPlaylist playlist) =>
      _openToken(playlist.shareToken);

  Future<void> _openToken(String shareToken) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SharedPlaylistScreen(
        shareToken: shareToken,
        controller: widget.controller,
        player: widget.player,
        onSaved: widget.onSaved,
        onSignIn: widget.onSignIn,
      ),
    ));
    if (mounted) await widget.controller.loadPopular();
  }

  Future<void> _like(PublicPlaylist playlist) async {
    if (!widget.controller.signedIn) {
      askToSignIn(context, action: 'پسندیدن', onSignIn: widget.onSignIn);
      return;
    }
    final result =
        await widget.controller.setLike(playlist.shareToken, playlist.likes);
    if (!mounted || result == LikeResult.done) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result == LikeResult.gone
          ? 'این فهرست پخش دیگر عمومی نیست.'
          : 'پسندیدن ثبت نشد. دوباره تلاش کن.'),
    ));
    if (result == LikeResult.gone) await widget.controller.loadPopular();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('فهرست‌های پخش محبوب'),
        actions: [
          // Readable before signing up, as the stores expect.
          if (widget.onSignIn != null && !controller.signedIn)
            IconButton(
              onPressed: () => openSitePage(context, '/privacy',
                  siteUri: widget.siteUri, openLink: widget.openLink),
              tooltip: 'حریم خصوصی',
              icon: const Icon(NafirIcons.shieldCheck),
            ),
          if (widget.onSignIn != null && !controller.signedIn)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: FilledButton(
                onPressed: widget.onSignIn,
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('ورود / ثبت‌نام'),
              ),
            ),
        ],
      ),
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
                      text: 'فهرست‌های پخش محبوب بارگذاری نشد.',
                      action: FilledButton.icon(
                        onPressed: controller.loadPopular,
                        icon: const Icon(NafirIcons.arrowsClockwise),
                        label: const Text('تلاش دوباره'),
                      ),
                    ),
                  _ when popular.isEmpty => const _Notice(
                      icon: NafirIcons.globe,
                      text: 'هنوز فهرست پخش عمومی‌ای نیست. وقتی فهرست پخشی را '
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
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.only(start: 14, end: 8),
        minTileHeight: 76,
        horizontalTitleGap: 14,
        leading: Container(
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
        title: Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            playlist.isOwner ? 'فهرست پخش خودت' : playlist.owner,
            '${persianDigits(playlist.trackCount)} آهنگ',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        trailing: PlaylistLikeButton(
          likes: playlist.likes,
          onPressed: onLike,
          compact: true,
        ),
        onTap: onOpen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
