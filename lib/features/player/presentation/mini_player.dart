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
                  final summary = _TrackSummary(track: track, status: status);
                  final controls = _PlaybackControls(
                    player: player,
                    status: status,
                    busy: busy,
                    playing: playing,
                  );

                  return Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      compact ? 12 : 20,
                      10,
                      compact ? 12 : 20,
                      8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (compact) ...[
                          summary,
                          const SizedBox(height: 8),
                          Center(child: controls),
                        ] else
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

class _TrackSummary extends StatelessWidget {
  const _TrackSummary({required this.track, required this.status});

  final Track track;
  final PlayerStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [NafirGlass.primary, Color(0xFF8D3B79)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: NafirGlass.primary.withValues(alpha: 0.2),
                offset: const Offset(0, 7),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Icon(Icons.graphic_eq, color: Color(0xFFFFF5F5)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
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
              if (status == PlayerStatus.error)
                Text(
                  'پخش ناموفق بود. دوباره تلاش کن.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                )
              else
                Text(
                  track.artist?.trim().isNotEmpty == true
                      ? track.artist!
                      : 'در حال پخش',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
            ],
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
