import 'package:nafir/core/persian_digits.dart';
import 'package:flutter/material.dart';
import 'package:nafir/core/design/design.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/core/links/open_link.dart';
import 'package:nafir/core/links/site_page.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
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
  /// The playlist being fetched to play, so its button shows progress.
  String? _playing;

  Future<void> _play(PublicPlaylist playlist) async {
    setState(() => _playing = playlist.shareToken);
    try {
      final shared = await widget.controller.openShared(playlist.shareToken);
      if (!mounted) return;
      if (shared.tracks.isEmpty) {
        _say('این فهرست پخش آهنگی ندارد.');
      } else {
        await widget.player.playFrom(shared.tracks, 0);
      }
    } on SharedPlaylistUnavailable {
      _say('این فهرست پخش دیگر عمومی نیست.');
      await widget.controller.loadPopular();
    } catch (_) {
      _say('پخش این فهرست شروع نشد. دوباره تلاش کن.');
    } finally {
      if (mounted) setState(() => _playing = null);
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

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
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final popular = controller.popular;
            return switch (controller.popularStatus) {
              PlaylistsStatus.loading when popular.isEmpty =>
                const NafirStateView.loading(
                    title: 'در حال دریافت فهرست‌های محبوب…'),
              PlaylistsStatus.error when popular.isEmpty =>
                NafirStateView.error(
                  icon: NafirIcons.cloudSlash,
                  title: 'فهرست‌های پخش محبوب بارگذاری نشد.',
                  message: 'اتصال را بررسی کن و دوباره تلاش کن.',
                  action: FilledButton.icon(
                    onPressed: controller.loadPopular,
                    icon: const Icon(NafirIcons.arrowsClockwise),
                    label: const Text('تلاش دوباره'),
                  ),
                ),
              _ when popular.isEmpty => const NafirStateView(
                  icon: NafirIcons.globe,
                  title: 'هنوز فهرست پخش عمومی‌ای نیست',
                  message: 'وقتی فهرست پخشی را به اشتراک می‌گذاری، «عمومی» '
                      'را انتخاب کن تا اینجا نشان داده شود.',
                ),
              _ => RefreshIndicator(
                  onRefresh: controller.loadPopular,
                  child: _PopularGrid(
                    popular: popular,
                    playing: _playing,
                    isLiking: controller.isLiking,
                    onOpen: _open,
                    onPlay: _play,
                    onLike: _like,
                  ),
                ),
            };
          },
        ),
      ),
    );
  }
}

/// The popular playlists as square tiles, two across on a phone and more
/// on wider screens, inside a centred column.
class _PopularGrid extends StatelessWidget {
  const _PopularGrid({
    required this.popular,
    required this.playing,
    required this.isLiking,
    required this.onOpen,
    required this.onPlay,
    required this.onLike,
  });

  final List<PublicPlaylist> popular;

  /// The playlist whose tracks are being fetched to play, if any.
  final String? playing;
  final bool Function(String shareToken) isLiking;
  final ValueChanged<PublicPlaylist> onOpen;
  final ValueChanged<PublicPlaylist> onPlay;
  final ValueChanged<PublicPlaylist> onLike;

  /// Below the square cover: the title and count beside a 48 px like.
  static const _textHeight = NafirSpace.sm + NafirSpace.target + NafirSpace.xs;

  @override
  Widget build(BuildContext context) {
    // The scaffold extends the body under the mini player and reports the
    // player's height, with the system inset, as bottom padding.
    final bottom = MediaQuery.paddingOf(context).bottom + NafirSpace.xxl;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.clamp(0.0, NafirSpace.pageWidth);
      final gutter = width >= 600 ? NafirSpace.xxl : NafirSpace.lg;
      final inner = width - gutter * 2;
      final columns = (inner / 200).floor().clamp(2, 5);
      final tile = (inner - NafirSpace.md * (columns - 1)) / columns;
      final side = (constraints.maxWidth - width) / 2 + gutter;
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, NafirSpace.md, side, bottom),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: NafirSpace.lg,
                crossAxisSpacing: NafirSpace.md,
                mainAxisExtent: tile + _textHeight,
              ),
              itemCount: popular.length,
              itemBuilder: (context, index) {
                final playlist = popular[index];
                return _PopularTile(
                  playlist: playlist,
                  rank: index + 1,
                  loading: playing == playlist.shareToken,
                  onOpen: () => onOpen(playlist),
                  onPlay: () => onPlay(playlist),
                  onLike: isLiking(playlist.shareToken)
                      ? null
                      : () => onLike(playlist),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

/// One popular playlist: a mosaic cover with its rank and a play button,
/// then its name, track count and likes. The owner is never shown.
class _PopularTile extends StatelessWidget {
  const _PopularTile({
    required this.playlist,
    required this.rank,
    required this.loading,
    required this.onOpen,
    required this.onPlay,
    required this.onLike,
  });

  final PublicPlaylist playlist;
  final int rank;
  final bool loading;
  final VoidCallback onOpen;
  final VoidCallback onPlay;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = '${persianDigits(playlist.trackCount)} آهنگ';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  button: true,
                  label: 'رتبهٔ ${persianDigits(rank)}: ${playlist.name}، '
                      '$count',
                  excludeSemantics: true,
                  child: Material(
                    clipBehavior: Clip.antiAlias,
                    shape: const RoundedRectangleBorder(
                        borderRadius: NafirRadii.surface),
                    child: InkWell(
                      onTap: onOpen,
                      child: _MosaicCover(
                          seed: playlist.shareToken,
                          tiles: playlist.trackCount),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: NafirSpace.sm,
                start: NafirSpace.sm,
                child: _RankBadge(rank: rank),
              ),
              PositionedDirectional(
                bottom: NafirSpace.sm,
                end: NafirSpace.sm,
                child: IconButton.filled(
                  tooltip: 'پخش ${playlist.name}',
                  onPressed:
                      loading || playlist.trackCount == 0 ? null : onPlay,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(NafirSpace.target),
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                  ),
                  icon: loading
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: scheme.onPrimary),
                        )
                      : const Icon(NafirIcons.playFill),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NafirSpace.sm),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onOpen,
                borderRadius: NafirRadii.control,
                child: Padding(
                  padding:
                      const EdgeInsetsDirectional.only(start: NafirSpace.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        playlist.isOwner ? 'فهرست پخش خودت · $count' : count,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PlaylistLikeButton(
              likes: playlist.likes,
              onPressed: onLike,
              compact: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// The playlist's place in the list, on its cover.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = rank <= 3;
    return Container(
      constraints: const BoxConstraints(minWidth: 32),
      padding: const EdgeInsets.symmetric(
          horizontal: NafirSpace.sm, vertical: NafirSpace.xxs),
      decoration: BoxDecoration(
        color: top ? theme.colorScheme.primary : NafirColors.scrim,
        borderRadius: BorderRadius.circular(NafirRadii.pill),
      ),
      child: Text(
        persianDigits(rank),
        textAlign: TextAlign.center,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: top ? theme.colorScheme.onPrimary : NafirColors.onSurface,
        ),
      ),
    );
  }
}

/// A cover made of up to four tinted squares, one per track, seeded by the
/// playlist so it keeps its look. The API lists no artwork for popular
/// playlists yet, so the tints stand in for it.
class _MosaicCover extends StatelessWidget {
  const _MosaicCover({required this.seed, required this.tiles});

  final String seed;
  final int tiles;

  @override
  Widget build(BuildContext context) {
    Widget square(int i) => ColoredBox(
          color: artworkTint('$seed-$i'),
          child: Center(
            child: Icon(NafirIcons.musicNotes,
                color: NafirColors.onSurface.withValues(alpha: 0.32)),
          ),
        );
    final count = tiles.clamp(1, 4);
    if (count < 4) {
      // Fewer than four tracks: one tint, so the cover never looks broken.
      return square(0);
    }
    return Column(
      children: [
        for (final row in const [0, 2])
          Expanded(
            child: Row(
              children: [
                for (final column in const [0, 1])
                  Expanded(child: square(row + column)),
              ],
            ),
          ),
      ],
    );
  }
}
