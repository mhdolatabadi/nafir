import 'package:flutter/material.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/features/player/application/playback_settings.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/player/presentation/playback_controls.dart';
import 'package:nafir/features/settings/presentation/crossfade_setting.dart';
import 'package:nafir/features/settings/presentation/loudness_setting.dart';

/// Playback controls backed by the same controller as the now-playing screen.
class PlaybackSettingsSection extends StatelessWidget {
  const PlaybackSettingsSection({super.key, required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: player,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
                    child: Text('پخش',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(NafirIcons.moonStars),
                          title: const Text('زمان‌سنج خواب'),
                          subtitle: Text(sleepTimerStatus(player) ?? 'خاموش'),
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            useSafeArea: true,
                            isScrollControlled: true,
                            builder: (_) => SleepTimerSheet(player: player),
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const Icon(NafirIcons.gauge),
                          title: const Text('سرعت پخش'),
                          trailing: Text(formatSpeed(player.speed)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Slider(
                              key: const ValueKey('playback-speed-slider'),
                              value: playbackSpeeds
                                  .indexOf(player.speed)
                                  .clamp(0, playbackSpeeds.length - 1)
                                  .toDouble(),
                              max: (playbackSpeeds.length - 1).toDouble(),
                              divisions: playbackSpeeds.length - 1,
                              label: formatSpeed(player.speed),
                              semanticFormatterCallback: (value) =>
                                  formatSpeed(playbackSpeeds[value.round()]),
                              onChanged: (value) => player
                                  .setSpeed(playbackSpeeds[value.round()]),
                            ),
                          ),
                        ),
                        if (player.supportsCrossfade)
                          CrossfadeSetting(player: player),
                        LoudnessSetting(player: player),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
