import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nafir/core/persian_digits.dart';
import 'package:nafir/features/journey/application/listening_journey.dart';
import 'package:nafir/features/journey/application/monthly_card.dart';
import 'package:nafir/features/journey/data/monthly_card_export.dart';
import 'package:nafir/features/library/data/track.dart';

class MonthlyCardSection extends StatefulWidget {
  const MonthlyCardSection(
      {super.key,
      required this.journey,
      required this.tracks,
      this.saver,
      this.renderer});
  final ListeningJourney journey;
  final List<Track> tracks;
  final MonthlyCardSaver? saver;
  final Future<Uint8List> Function(MonthlyListeningCard)? renderer;

  @override
  State<MonthlyCardSection> createState() => _MonthlyCardSectionState();
}

class _MonthlyCardSectionState extends State<MonthlyCardSection> {
  String? _month;
  Uint8List? _png;
  MonthlyListeningCard? _snapshot;
  int? _generation;
  bool _busy = false;
  String? _message;

  Future<void> _render(String month) async {
    final generation = widget.journey.accountGeneration;
    final snapshot = MonthlyListeningCard(
        month: month,
        plays: widget.journey.playsForMonth(month),
        library: widget.tracks);
    setState(() {
      _busy = true;
      _message = null;
      _png = null;
      _generation = generation;
    });
    try {
      final png =
          await (widget.renderer?.call(snapshot) ?? snapshot.renderPng());
      if (!mounted ||
          widget.journey.accountGeneration != generation ||
          !widget.journey.enabled) {
        return;
      }
      setState(() {
        _png = png;
        _snapshot = snapshot;
        _generation = generation;
      });
    } catch (_) {
      if (mounted && widget.journey.accountGeneration == generation) {
        setState(() => _message = 'ساخت کارت ناموفق بود؛ دوباره تلاش کن.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final png = _png;
    final card = _snapshot;
    if (png == null ||
        card == null ||
        _busy ||
        _generation != widget.journey.accountGeneration ||
        !widget.journey.enabled) {
      return;
    }
    final generation = _generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final saved = await (widget.saver ?? FilePickerMonthlyCardSaver())
          .save(png, 'rhythmo-${card.month}.png');
      if (mounted && generation == widget.journey.accountGeneration) {
        setState(() => _message = switch (saved) {
              MonthlyCardSaveResult.saved => 'کارت ذخیره شد.',
              MonthlyCardSaveResult.cancelled => 'ذخیره لغو شد.',
              MonthlyCardSaveResult.downloadStarted =>
                'دریافت تصویر به مرورگر سپرده شد.',
            });
      }
    } catch (_) {
      if (mounted && generation == widget.journey.accountGeneration) {
        setState(() => _message = 'ذخیرهٔ کارت ناموفق بود؛ دوباره تلاش کن.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.journey,
        builder: (context, _) {
          if (!widget.journey.ready || !widget.journey.enabled) {
            return const SizedBox.shrink();
          }
          final months = widget.journey.months;
          final month = months.contains(_month) ? _month! : months.first;
          final plays = widget.journey.playsForMonth(month);
          final card = MonthlyListeningCard(
              month: month, plays: plays, library: widget.tracks);
          final previewValid = _png != null &&
              _snapshot?.month == month &&
              _generation == widget.journey.accountGeneration &&
              mapEquals(_snapshot?.plays, plays);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('خاطرهٔ شنیدن',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('${widget.journey.accountGeneration}:$month'),
                  initialValue: month,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'ماه شنیدن'),
                  items: [
                    for (final key in months)
                      DropdownMenuItem(
                          value: key, child: Text(listeningMonthLabel(key)))
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _month = value;
                            _png = null;
                            _message = null;
                          }),
                ),
                const SizedBox(height: 12),
                Text('${persianDigits(card.total)} بار شنیدن معنادار · '
                    '${persianDigits(plays.length)} آهنگ متفاوت'),
                for (final track in card.topTracks)
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(track.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text('${persianDigits(plays[track.id]!)} بار')),
                if (plays.isEmpty)
                  const Text('برای این ماه هنوز شنیدنی ثبت نشده است.'),
                const SizedBox(height: 12),
                const Text('کارت شامل آمار و نام آهنگ‌های محبوب است. '
                    'پیش‌نمایش را ببین و اگر خواستی تصویرش را ذخیره یا برای دیگران بفرست.'),
                const SizedBox(height: 12),
                if (!previewValid)
                  OutlinedButton(
                      onPressed:
                          _busy || plays.isEmpty ? null : () => _render(month),
                      child:
                          Text(_busy ? 'در حال ساخت کارت…' : 'پیش‌نمایش کارت')),
                if (previewValid) ...[
                  Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Image.memory(_png!,
                              semanticLabel: 'کارت شنیداری '
                                  '${listeningMonthLabel(month)}، ${persianDigits(card.total)} بار شنیدن',
                              fit: BoxFit.contain))),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: _busy ? null : _save,
                      child:
                          Text(_busy ? 'در حال ذخیره…' : 'ذخیرهٔ تصویر کارت')),
                ],
                if (_message != null &&
                    _generation == widget.journey.accountGeneration)
                  Semantics(liveRegion: true, child: Text(_message!)),
              ]);
        },
      );
}
