import 'package:flutter/material.dart';
import 'package:nafir/core/widgets/glass_surface.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/play_queue.dart';
import 'package:nafir/features/player/application/player_controller.dart';

/// Responsive now-playing surface with track identity, playback controls,
/// and progress.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key, required this.player});

  final PlayerController player;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double? _dragMs;

  static String _format(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _NowPlayingScreen(player: widget.player),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        final player = widget.player;
        final track = player.track;
        if (track == null) return const SizedBox.shrink();

        final status = player.status;
        final durationMs = player.duration?.inMilliseconds ?? 0;
        final positionMs =
            player.position.inMilliseconds.clamp(0, durationMs).toDouble();
        final busy =
            status == PlayerStatus.loading || status == PlayerStatus.buffering;
        final playing =
            status == PlayerStatus.playing || status == PlayerStatus.buffering;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GlassSurface(
            radius: 24,
            blur: 24,
            tint: NafirGlass.primary,
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final summary = _TrackSummary(
                    track: track,
                    status: status,
                    onTap: _openNowPlaying,
                  );
                  final controls = _PlaybackControls(
                    player: player,
                    status: status,
                    busy: busy,
                    playing: playing,
                  );

                  if (compact) {
                    return _CompactMiniPlayer(
                      track: track,
                      status: status,
                      player: player,
                      busy: busy,
                      playing: playing,
                      progress: durationMs > 0
                          ? (positionMs / durationMs).clamp(0.0, 1.0)
                          : null,
                      onOpen: _openNowPlaying,
                    );
                  }

                  return Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(child: summary),
                            const SizedBox(width: 24),
                            controls,
                          ],
                        ),
                        const SizedBox(height: 4),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(
                            children: [
                              _TimeLabel(_format(player.position)),
                              Expanded(
                                child: Slider(
                                  value: _dragMs ?? positionMs,
                                  max: durationMs > 0
                                      ? durationMs.toDouble()
                                      : 1,
                                  semanticFormatterCallback: (value) => _format(
                                    Duration(milliseconds: value.round()),
                                  ),
                                  onChanged: durationMs > 0
                                      ? (value) =>
                                          setState(() => _dragMs = value)
                                      : null,
                                  onChangeEnd: durationMs > 0
                                      ? (value) {
                                          setState(() => _dragMs = null);
                                          player.seek(
                                            Duration(
                                              milliseconds: value.round(),
                                            ),
                                          );
                                        }
                                      : null,
                                ),
                              ),
                              _TimeLabel(
                                _format(player.duration ?? Duration.zero),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompactMiniPlayer extends StatelessWidget {
  const _CompactMiniPlayer({
    required this.track,
    required this.status,
    required this.player,
    required this.busy,
    required this.playing,
    required this.progress,
    required this.onOpen,
  });

  final Track track;
  final PlayerStatus status;
  final PlayerController player;
  final bool busy;
  final bool playing;
  final double? progress;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 9, 8, 8),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onOpen,
                child: _MiniArtwork(track: track, status: status, size: 44),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _MiniTrackText(track: track, status: status),
                  ),
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'قبلی',
                      onPressed: player.previous,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    if (busy)
                      const SizedBox.square(
                        dimension: 42,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    else
                      IconButton.filled(
                        tooltip: status == PlayerStatus.error
                            ? 'تلاش دوباره'
                            : playing
                                ? 'توقف'
                                : 'پخش',
                        onPressed: player.toggle,
                        icon: Icon(
                          status == PlayerStatus.error
                              ? Icons.refresh
                              : playing
                                  ? Icons.pause
                                  : Icons.play_arrow,
                        ),
                      ),
                    IconButton(
                      tooltip: 'بعدی',
                      onPressed: player.next,
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (progress case final value?)
          PositionedDirectional(
            start: 18,
            end: 18,
            bottom: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 2,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
          ),
      ],
    );
  }
}

class _TrackSummary extends StatelessWidget {
  const _TrackSummary({
    required this.track,
    required this.status,
    required this.onTap,
  });

  final Track track;
  final PlayerStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Row(
        children: [
          _MiniArtwork(track: track, status: status, size: 44),
          const SizedBox(width: 12),
          Expanded(child: _MiniTrackText(track: track, status: status)),
        ],
      ),
    );
  }
}

class _MiniArtwork extends StatelessWidget {
  const _MiniArtwork({
    required this.track,
    required this.status,
    required this.size,
  });

  final Track track;
  final PlayerStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = status == PlayerStatus.error
        ? Icons.error_outline
        : track.isLocal
            ? Icons.phone_android
            : Icons.music_note;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size >= 44 ? 14 : 12),
        boxShadow: [
          BoxShadow(
            color: NafirGlass.primary.withValues(alpha: 0.18),
            offset: const Offset(0, 7),
            blurRadius: 18,
          ),
        ],
      ),
      child: Icon(
        icon,
        size: size * 0.36,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _MiniTrackText extends StatelessWidget {
  const _MiniTrackText({required this.track, required this.status});

  final Track track;
  final PlayerStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      // The mini player is the scaffold's bottom bar, which may be as tall
      // as the screen; a Column that took all of it covered the library.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          status == PlayerStatus.error
              ? 'پخش ناموفق بود. دوباره تلاش کن.'
              : track.artist?.trim().isNotEmpty == true
                  ? track.artist!
                  : track.isLocal
                      ? 'روی دستگاه'
                      : 'روی سرور',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: status == PlayerStatus.error
                    ? colors.error
                    : colors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.player,
    required this.status,
    required this.busy,
    required this.playing,
  });

  final PlayerController player;
  final PlayerStatus status;
  final bool busy;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Toggle(
            tooltip: player.shuffle ? 'پخش تصادفی: روشن' : 'پخش تصادفی',
            icon: Icons.shuffle,
            active: player.shuffle,
            onPressed: player.toggleShuffle,
          ),
          IconButton(
            tooltip: 'قبلی',
            onPressed: player.previous,
            icon: const Icon(Icons.skip_previous),
          ),
          const SizedBox(width: 4),
          if (busy)
            Semantics(
              label: 'در حال آماده‌سازی پخش',
              child: const SizedBox.square(
                dimension: 48,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else
            IconButton.filled(
              tooltip: status == PlayerStatus.error
                  ? 'تلاش دوباره'
                  : playing
                      ? 'توقف'
                      : 'پخش',
              iconSize: 28,
              onPressed: player.toggle,
              icon: Icon(
                status == PlayerStatus.error
                    ? Icons.refresh
                    : playing
                        ? Icons.pause
                        : Icons.play_arrow,
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'بعدی',
            onPressed: player.next,
            icon: const Icon(Icons.skip_next),
          ),
          _Toggle(
            tooltip: switch (player.repeat) {
              QueueRepeat.off => 'تکرار: خاموش',
              QueueRepeat.all => 'تکرار: همه',
              QueueRepeat.one => 'تکرار: همین آهنگ',
            },
            icon: player.repeat == QueueRepeat.one
                ? Icons.repeat_one
                : Icons.repeat,
            active: player.repeat != QueueRepeat.off,
            onPressed: player.cycleRepeat,
          ),
        ],
      ),
    );
  }
}

class _NowPlayingScreen extends StatefulWidget {
  const _NowPlayingScreen({required this.player});

  final PlayerController player;

  @override
  State<_NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<_NowPlayingScreen> {
  double? _dragMs;

  static String _format(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        final player = widget.player;
        final track = player.track;
        if (track == null) {
          return const Scaffold(body: SizedBox.shrink());
        }

        final durationMs = player.duration?.inMilliseconds ?? 0;
        final positionMs =
            player.position.inMilliseconds.clamp(0, durationMs).toDouble();
        final status = player.status;
        final busy =
            status == PlayerStatus.loading || status == PlayerStatus.buffering;
        final playing =
            status == PlayerStatus.playing || status == PlayerStatus.buffering;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'بستن',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            title: const Text('در حال پخش'),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'صف پخش',
                onPressed: () {},
                icon: const Icon(Icons.queue_music),
              ),
            ],
          ),
          body: NafirBackdrop(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                child: Column(
                  children: [
                    const Spacer(),
                    _MiniArtwork(track: track, status: status, size: 260),
                    const SizedBox(height: 34),
                    Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      track.artist?.trim().isNotEmpty == true
                          ? track.artist!
                          : track.isLocal
                              ? 'روی دستگاه'
                              : 'روی سرور',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const Spacer(),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Column(
                        children: [
                          Slider(
                            value: _dragMs ?? positionMs,
                            max: durationMs > 0 ? durationMs.toDouble() : 1,
                            semanticFormatterCallback: (value) => _format(
                              Duration(milliseconds: value.round()),
                            ),
                            onChanged: durationMs > 0
                                ? (value) => setState(() => _dragMs = value)
                                : null,
                            onChangeEnd: durationMs > 0
                                ? (value) {
                                    setState(() => _dragMs = null);
                                    player.seek(
                                      Duration(milliseconds: value.round()),
                                    );
                                  }
                                : null,
                          ),
                          Row(
                            children: [
                              _TimeLabel(_format(player.position)),
                              const Spacer(),
                              _TimeLabel(
                                _format(player.duration ?? Duration.zero),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _Toggle(
                            tooltip: player.shuffle
                                ? 'پخش تصادفی: روشن'
                                : 'پخش تصادفی',
                            icon: Icons.shuffle,
                            active: player.shuffle,
                            onPressed: player.toggleShuffle,
                          ),
                          IconButton(
                            tooltip: 'قبلی',
                            iconSize: 34,
                            onPressed: player.previous,
                            icon: const Icon(Icons.skip_previous),
                          ),
                          if (busy)
                            const SizedBox.square(
                              dimension: 64,
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              ),
                            )
                          else
                            IconButton.filled(
                              tooltip: status == PlayerStatus.error
                                  ? 'تلاش دوباره'
                                  : playing
                                      ? 'توقف'
                                      : 'پخش',
                              iconSize: 36,
                              onPressed: player.toggle,
                              icon: Icon(
                                status == PlayerStatus.error
                                    ? Icons.refresh
                                    : playing
                                        ? Icons.pause
                                        : Icons.play_arrow,
                              ),
                            ),
                          IconButton(
                            tooltip: 'بعدی',
                            iconSize: 34,
                            onPressed: player.next,
                            icon: const Icon(Icons.skip_next),
                          ),
                          _Toggle(
                            tooltip: switch (player.repeat) {
                              QueueRepeat.off => 'تکرار: خاموش',
                              QueueRepeat.all => 'تکرار: همه',
                              QueueRepeat.one => 'تکرار: همین آهنگ',
                            },
                            icon: player.repeat == QueueRepeat.one
                                ? Icons.repeat_one
                                : Icons.repeat,
                            active: player.repeat != QueueRepeat.off,
                            onPressed: player.cycleRepeat,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A mode button with both color and background feedback when selected.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      isSelected: active,
      onPressed: onPressed,
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(
          active ? colors.onSecondaryContainer : colors.onSurfaceVariant,
        ),
        backgroundColor: WidgetStatePropertyAll(
          active ? colors.secondaryContainer : Colors.transparent,
        ),
      ),
      icon: Icon(icon),
    );
  }
}
