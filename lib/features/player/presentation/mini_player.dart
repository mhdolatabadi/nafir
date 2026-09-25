import 'package:flutter/material.dart';
import 'package:nafir/features/player/application/play_queue.dart';
import 'package:nafir/features/player/application/player_controller.dart';

/// The now-playing bar: title, play/pause and a seek slider.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key, required this.player});

  final PlayerController player;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  /// Slider position while the user drags it, so it does not jump back.
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
        return Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(track.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (status == PlayerStatus.error)
                              Text(
                                'پخش ناموفق بود. دوباره تلاش کن.',
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error),
                              )
                            else if (track.artist != null)
                              Text(track.artist!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      // Media controls and the progress bar follow the
                      // direction of time, so they are not mirrored in RTL.
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Toggle(
                              tooltip: 'پخش تصادفی',
                              icon: Icons.shuffle,
                              active: player.shuffle,
                              onPressed: player.toggleShuffle,
                            ),
                            IconButton(
                              tooltip: 'قبلی',
                              onPressed: player.previous,
                              icon: const Icon(Icons.skip_previous),
                            ),
                            if (busy)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox.square(
                                  dimension: 24,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            else
                              IconButton(
                                tooltip: status == PlayerStatus.error
                                    ? 'تلاش دوباره'
                                    : playing
                                        ? 'توقف'
                                        : 'پخش',
                                iconSize: 32,
                                onPressed: player.toggle,
                                icon: Icon(status == PlayerStatus.error
                                    ? Icons.refresh
                                    : playing
                                        ? Icons.pause
                                        : Icons.play_arrow),
                              ),
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
                      ),
                    ],
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        Text(_format(player.position),
                            style: Theme.of(context).textTheme.labelSmall),
                        Expanded(
                          child: Slider(
                            value: _dragMs ?? positionMs,
                            max: durationMs > 0 ? durationMs.toDouble() : 1,
                            onChanged: durationMs > 0
                                ? (value) => setState(() => _dragMs = value)
                                : null,
                            onChangeEnd: durationMs > 0
                                ? (value) {
                                    setState(() => _dragMs = null);
                                    player.seek(
                                        Duration(milliseconds: value.round()));
                                  }
                                : null,
                          ),
                        ),
                        Text(_format(player.duration ?? Duration.zero),
                            style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A mode button that is highlighted while its mode is on.
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
      color: active ? colors.primary : colors.onSurfaceVariant,
      icon: Icon(icon),
    );
  }
}
