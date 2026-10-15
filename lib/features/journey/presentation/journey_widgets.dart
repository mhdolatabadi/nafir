import 'package:rhythmo/features/journey/presentation/monthly_card_section.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:rhythmo/core/persian_digits.dart';
import 'package:rhythmo/core/widgets/rhythmo_icons.dart';
import 'package:rhythmo/features/journey/application/listening_journey.dart';
import 'package:rhythmo/features/library/data/track.dart';
import 'package:rhythmo/features/player/application/player_controller.dart';

class JourneySetting extends StatelessWidget {
  const JourneySetting({super.key, required this.journey});
  final ListeningJourney journey;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: journey,
        builder: (context, _) => SwitchListTile(
          title: const Text('سفر شنیداری'),
          subtitle: const Text('پیشرفت و دستاوردهای خصوصی روی این دستگاه'),
          value: journey.enabled,
          onChanged: journey.ready ? journey.setEnabled : null,
        ),
      );
}

class JourneyCard extends StatelessWidget {
  const JourneyCard({
    super.key,
    required this.journey,
    required this.tracks,
    required this.player,
  });
  final ListeningJourney journey;
  final List<Track> tracks;
  final PlayerController player;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: journey,
        builder: (context, _) {
          if (!journey.ready || !journey.enabled || tracks.isEmpty) {
            return const SizedBox.shrink();
          }
          final goal = min(5, tracks.map((t) => t.id).toSet().length);
          final count = min(
            goal,
            tracks.map((t) => t.id).toSet().where(journey.heardThisWeek).length,
          );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(RhythmoIcons.musicNotes),
                  title: const Text('سفر شنیداری این هفته'),
                  subtitle: Text(
                    count == goal
                        ? 'سفر این هفته کامل شد'
                        : '${persianDigits(count)} از ${persianDigits(goal)} آهنگ متفاوت',
                  ),
                  trailing: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _JourneyScreen(
                          journey: journey,
                          accountGeneration: journey.accountGeneration,
                          tracks: tracks,
                          player: player,
                        ),
                      ),
                    ),
                    child: const Text('سفر من'),
                  ),
                ),
                Semantics(
                  label: 'پیشرفت سفر شنیداری',
                  value: '${persianDigits(count)} از ${persianDigits(goal)}',
                  child: LinearProgressIndicator(value: count / goal),
                ),
              ],
            ),
          );
        },
      );
}

class _JourneyScreen extends StatelessWidget {
  const _JourneyScreen({
    required this.accountGeneration,
    required this.journey,
    required this.tracks,
    required this.player,
  });
  final ListeningJourney journey;
  final List<Track> tracks;
  final PlayerController player;
  final int accountGeneration;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('سفر من')),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: journey,
            builder: (context, _) {
              if (!journey.ready ||
                  journey.accountGeneration != accountGeneration) {
                return const Center(
                    child:
                        Text('برای دیدن سفر این حساب، دوباره وارد صفحه شو.'));
              }
              final suggestions = journey.suggestions(tracks);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text('از کتابخانه‌ات دوباره کشف کن'),
                      const SizedBox(height: 8),
                      const Text(
                        'شنیدن کوتاه و جلو بردن آهنگ، پیشرفت حساب نمی‌شود. '
                        'هفته از شنبه شروع می‌شود؛ دستاوردهایت باقی می‌مانند.',
                      ),
                      const SizedBox(height: 16),
                      if (suggestions.isEmpty)
                        const Text(
                          'همهٔ آهنگ‌های این مجموعه را این هفته شنیده‌ای.',
                        ),
                      for (final track in suggestions)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: track.artist == null
                              ? null
                              : Text(
                                  track.artist!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: IconButton(
                            tooltip: 'پخش ${track.title}',
                            icon: const Icon(RhythmoIcons.playFill),
                            onPressed: () => player.playFrom(
                              suggestions,
                              suggestions.indexOf(track),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text(
                        'دستاوردها',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      for (final badge in [
                        (1, 'اولین کشف'),
                        (10, 'کاوشگر کتابخانه'),
                        (50, 'گنجینهٔ شنیداری'),
                      ])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            journey.discoveries >= badge.$1
                                ? RhythmoIcons.checkCircle
                                : RhythmoIcons.musicNote,
                          ),
                          title: Text(badge.$2),
                          subtitle: Text(
                            journey.discoveries >= badge.$1
                                ? 'به دست آوردی'
                                : '${persianDigits(journey.discoveries)} از '
                                    '${persianDigits(badge.$1)} آهنگ متفاوت',
                          ),
                        ),
                      const SizedBox(height: 24),
                      MonthlyCardSection(journey: journey, tracks: tracks),
                      const SizedBox(height: 16),
                      const Text(
                        'این پیشرفت خصوصی است و فعلاً فقط روی همین دستگاه ذخیره می‌شود.',
                      ),
                      if (journey.saveFailed)
                        const Text('ذخیرهٔ پیشرفت روی دستگاه ناموفق بود.'),
                      JourneySetting(journey: journey),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
}
