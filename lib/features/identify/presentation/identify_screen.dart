import 'package:flutter/material.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/core/persian_digits.dart';
import 'package:nafir/core/widgets/glass_surface.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/features/identify/application/identify_controller.dart';
import 'package:nafir/features/identify/data/snippet_recorder.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/player/presentation/mini_player.dart';
import 'package:nafir/features/player/presentation/now_playing_screen.dart';

/// The widest the identify column grows on desktop.
const identifyMaxWidth = 520.0;

/// Opens «این آهنگ چیه؟» from the start.
Future<void> openIdentify(BuildContext context, IdentifyController controller,
    PlayerController player) {
  controller.reset();
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => IdentifyScreen(controller: controller, player: player),
  ));
}

/// «این آهنگ چیه؟»: listens for a few seconds and says which song in
/// rhythmo is playing.
class IdentifyScreen extends StatefulWidget {
  const IdentifyScreen({
    super.key,
    required this.controller,
    required this.player,
  });

  final IdentifyController controller;
  final PlayerController player;

  @override
  State<IdentifyScreen> createState() => _IdentifyScreenState();
}

class _IdentifyScreenState extends State<IdentifyScreen> {
  IdentifyController get _controller => widget.controller;

  @override
  void dispose() {
    // Leaving stops the microphone at once.
    if (_controller.phase == IdentifyPhase.listening) _controller.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    final track = await _controller.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(track != null
          ? 'به کتابخانه اضافه شد.'
          : _controller.error ?? 'آهنگ اضافه نشد.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('این آهنگ چیه؟'),
        backgroundColor: NafirGlass.background,
      ),
      bottomNavigationBar: MiniPlayer(player: widget.player),
      body: NafirBackdrop(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 56,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: identifyMaxWidth),
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      child: KeyedSubtree(
                        key: ValueKey(_controller.phase),
                        child: _content(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final retry = FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
      onPressed: _controller.listen,
      icon: const Icon(NafirIcons.microphone),
      label: const Text('دوباره گوش بده'),
    );
    switch (_controller.phase) {
      case IdentifyPhase.ready:
        return _Intro(onListen: _controller.listen);
      case IdentifyPhase.unsupported:
        return const _Message(
          icon: NafirIcons.microphoneSlash,
          title: 'ضبط صدا اینجا ممکن نیست',
          detail: 'این دستگاه یا مرورگر به میکروفون دسترسی نمی‌دهد. '
              'از برنامهٔ اندروید یا مرورگر دیگری امتحان کنید.',
        );
      case IdentifyPhase.permissionDenied:
        return _Message(
          icon: NafirIcons.microphoneSlash,
          title: 'دسترسی به میکروفون داده نشد',
          detail: 'برای شناختن آهنگ، ریتمو باید چند ثانیه صدای اطراف را '
              'بشنود. دسترسی میکروفون را در تنظیمات دستگاه یا مرورگر روشن '
              'کنید و دوباره امتحان کنید.',
          action: retry,
        );
      case IdentifyPhase.listening:
        return _Listening(
          level: _controller.level,
          onCancel: _controller.cancel,
        );
      case IdentifyPhase.searching:
        return const _Message(
          icon: NafirIcons.waveform,
          title: 'در حال جستجو…',
          detail: 'صدای ضبط‌شده با آهنگ‌های در دسترس شما مقایسه می‌شود.',
          busy: true,
        );
      case IdentifyPhase.found:
        return _Result(
          match: _controller.match!,
          saving: _controller.saving,
          saved: _controller.saved,
          onPlay: () {
            final match = _controller.match!;
            widget.player.playFrom([match.track], 0);
            openNowPlaying(context, widget.player);
          },
          onSave: _save,
          onAgain: _controller.listen,
        );
      case IdentifyPhase.notFound:
        return _Message(
          icon: NafirIcons.musicNotesMinus,
          title: 'پیدا نشد',
          detail: 'فقط آهنگ‌هایی شناخته می‌شوند که در کتابخانهٔ شما، '
              'فهرست‌های پخش مشترک شما یا فهرست‌های پخش عمومی ریتمو هستند.',
          action: retry,
        );
      case IdentifyPhase.failed:
        return _Message(
          icon: NafirIcons.warningCircle,
          title: 'شناسایی انجام نشد',
          detail: _controller.error,
          action: retry,
        );
    }
  }
}

/// What happens, said before the microphone is asked for.
class _Intro extends StatelessWidget {
  const _Intro({required this.onListen});

  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'شروع گوش دادن',
          child: SizedBox.square(
            dimension: 132,
            child: IconButton.filled(
              tooltip: 'شروع گوش دادن',
              iconSize: 56,
              style: IconButton.styleFrom(
                shape: const CircleBorder(),
                fixedSize: const Size.square(132),
              ),
              onPressed: onListen,
              icon: const Icon(NafirIcons.microphoneStage),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'آهنگی که پخش می‌شود را بشناسید',
          textAlign: TextAlign.center,
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          'ریتمو ${persianDigits(snippetLength.inSeconds)} ثانیه از صدای '
          'اطراف را با میکروفون ضبط می‌کند و با آهنگ‌های کتابخانهٔ شما و '
          'فهرست‌های پخشی که به آن‌ها دسترسی دارید مقایسه می‌کند. صدای '
          'ضبط‌شده بعد از جستجو پاک می‌شود و جایی نگه داشته نمی‌شود.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
          onPressed: onListen,
          icon: const Icon(NafirIcons.microphone),
          label: const Text('گوش بده'),
        ),
      ],
    );
  }
}

/// The microphone is on: a ring that breathes with the sound, and how long
/// is left.
class _Listening extends StatelessWidget {
  const _Listening({required this.level, required this.onCancel});

  final double level;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          label: 'در حال گوش دادن',
          child: SizedBox.square(
            dimension: 168,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  width: 120 + 48 * level,
                  height: 120 + 48 * level,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary.withValues(alpha: 0.18),
                  ),
                ),
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary,
                  ),
                  child: Icon(NafirIcons.microphone,
                      size: 48, color: colors.onPrimary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'در حال گوش دادن…',
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'گوشی را نزدیک منبع صدا نگه دارید.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 240,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: snippetLength,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              borderRadius: BorderRadius.circular(4),
              semanticsLabel: 'زمان ضبط',
            ),
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(96, 48)),
          onPressed: onCancel,
          child: const Text('لغو'),
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.match,
    required this.saving,
    required this.saved,
    required this.onPlay,
    required this.onSave,
    required this.onAgain,
  });

  final SongMatch match;
  final bool saving;
  final bool saved;
  final VoidCallback onPlay;
  final VoidCallback onSave;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final track = match.track;
    final where = switch (match.source) {
      SongMatchSource.library => 'در کتابخانهٔ شما',
      SongMatchSource.playlist => 'در یک فهرست پخش مشترک',
      SongMatchSource.public => 'در یک فهرست پخش عمومی',
    };
    final percent = (match.confidence * 100).round().clamp(0, 100);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'پیدا شد',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(color: colors.primary),
        ),
        const SizedBox(height: 16),
        GlassSurface(
          radius: 24,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: trackTint(track),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(NafirIcons.musicNote,
                      size: 32, color: colors.onSurfaceVariant),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        trackSubtitle(track),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$where · اطمینان ${persianDigits(percent)}٪',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
          onPressed: onPlay,
          icon: const Icon(NafirIcons.playFill),
          label: const Text('پخش'),
        ),
        if (match.canSave) ...[
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            onPressed: saving || saved ? null : onSave,
            icon: Icon(saved ? NafirIcons.check : NafirIcons.plus),
            label: Text(saved
                ? 'در کتابخانهٔ شما'
                : saving
                    ? 'در حال افزودن…'
                    : 'افزودن به کتابخانه'),
          ),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: onAgain,
          icon: const Icon(NafirIcons.microphone),
          label: const Text('آهنگ دیگر'),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.detail,
    this.action,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const SizedBox.square(
            dimension: 56,
            child: CircularProgressIndicator(strokeWidth: 3),
          )
        else
          Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (detail != null) ...[
          const SizedBox(height: 10),
          Text(
            detail!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.7,
            ),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 24),
          action!,
        ],
      ],
    );
  }
}
