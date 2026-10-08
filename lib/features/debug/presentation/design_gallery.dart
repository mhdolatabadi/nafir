import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nafir/core/design/design.dart';
import 'package:nafir/core/persian_digits.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';

/// Opens the design gallery. It exists only in debug builds; release
/// builds never reach it.
void openDesignGallery(BuildContext context) {
  if (!kDebugMode) return;
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => const DesignGallery(),
  ));
}

/// Every token and shared component on one page, for checking the system by
/// eye and for screenshot tests at phone and desktop widths.
class DesignGallery extends StatelessWidget {
  const DesignGallery({super.key});

  static const colors = <(String, Color)>[
    ('background', NafirColors.background),
    ('surface', NafirColors.surface),
    ('surfaceStrong', NafirColors.surfaceStrong),
    ('surfaceRaised', NafirColors.surfaceRaised),
    ('primary', NafirColors.primary),
    ('primaryContainer', NafirColors.primaryContainer),
    ('secondary', NafirColors.secondary),
    ('secondaryContainer', NafirColors.secondaryContainer),
    ('onSurface', NafirColors.onSurface),
    ('onSurfaceVariant', NafirColors.onSurfaceVariant),
    ('outline', NafirColors.outline),
    ('outlineVariant', NafirColors.outlineVariant),
  ];

  static const spacing = <(String, double)>[
    ('xs', NafirSpace.xs),
    ('sm', NafirSpace.sm),
    ('md', NafirSpace.md),
    ('lg', NafirSpace.lg),
    ('xl', NafirSpace.xl),
    ('xxl', NafirSpace.xxl),
    ('xxxl', NafirSpace.xxxl),
    ('huge', NafirSpace.huge),
  ];

  static const radii = <(String, double)>[
    ('xs', NafirRadii.xs),
    ('sm', NafirRadii.sm),
    ('md', NafirRadii.md),
    ('lg', NafirRadii.lg),
    ('xl', NafirRadii.xl),
    ('sheet', NafirRadii.sheet),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final types = <(String, TextStyle?)>[
      ('displaySmall', text.displaySmall),
      ('headlineSmall', text.headlineSmall),
      ('titleLarge', text.titleLarge),
      ('titleMedium', text.titleMedium),
      ('bodyLarge', text.bodyLarge),
      ('bodyMedium', text.bodyMedium),
      ('labelLarge', text.labelLarge),
      ('labelMedium', text.labelMedium),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('سامانهٔ طراحی')),
      body: NafirBackdrop(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: NafirSpace.pageWidth),
            child: ListView(
              padding: nafirListBottomPadding(context, extra: NafirSpace.xxxl),
              children: [
                const NafirSectionHeader(title: 'رنگ‌ها'),
                _Wrap(children: [
                  for (final (name, color) in colors)
                    _Swatch(name: name, color: color),
                ]),
                const NafirSectionHeader(title: 'حروف'),
                for (final (name, style) in types)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: NafirSpace.xxl, vertical: NafirSpace.xs),
                    child: Text('$name · ریتمو، موسیقی تو', style: style),
                  ),
                const NafirSectionHeader(title: 'فاصله‌ها و گوشه‌ها'),
                _Wrap(children: [
                  for (final (name, value) in spacing)
                    _Measure(label: name, value: value, width: value),
                ]),
                _Wrap(children: [
                  for (final (name, value) in radii)
                    _Measure(label: name, value: value, radius: value),
                ]),
                const NafirSectionHeader(title: 'لایه‌های شیشه'),
                _Wrap(children: [
                  for (final (name, level) in const [
                    ('chrome', NafirGlassLevel.chrome),
                    ('panel', NafirGlassLevel.panel),
                    ('card', NafirGlassLevel.card),
                  ])
                    SizedBox(
                      width: 140,
                      height: 88,
                      child: GlassSurface.level(
                        level,
                        child: Center(child: Text(name)),
                      ),
                    ),
                ]),
                const NafirSectionHeader(
                  title: 'دکمه‌ها',
                  subtitle: 'با تب یا کلیدهای جهت، حلقهٔ تمرکز دیده می‌شود.',
                ),
                _Wrap(children: [
                  FilledButton(onPressed: () {}, child: const Text('اصلی')),
                  FilledButton.tonal(
                      onPressed: () {}, child: const Text('ثانویه')),
                  OutlinedButton(onPressed: () {}, child: const Text('دورخط')),
                  TextButton(onPressed: () {}, child: const Text('متنی')),
                  const FilledButton(onPressed: null, child: Text('غیرفعال')),
                  IconButton(
                    tooltip: 'نمونه',
                    onPressed: () {},
                    icon: const Icon(NafirIcons.heart),
                  ),
                  IconButton.filled(
                    tooltip: 'پخش',
                    onPressed: () {},
                    icon: const Icon(NafirIcons.playFill),
                  ),
                ]),
                const NafirSectionHeader(title: 'برچسب‌ها و لغزنده'),
                _Wrap(children: [
                  FilterChip(
                      label: const Text('انتخاب‌شده'),
                      selected: true,
                      onSelected: (_) {}),
                  FilterChip(label: const Text('معمولی'), onSelected: (_) {}),
                  const Chip(label: Text('فقط نمایش')),
                ]),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: NafirSpace.lg),
                  child: Slider(value: 0.4, onChanged: (_) {}),
                ),
                NafirSectionHeader(
                  title: 'ردیف آهنگ',
                  trailing: TextButton(
                    onPressed: () {},
                    child: const Text('همه'),
                  ),
                ),
                NafirTrackRow(
                  seed: 'gallery-1',
                  title:
                      'آهنگی با عنوانی بسیار بلند که هرگز در یک خط جا نمی‌شود',
                  subtitle: 'هنرمند',
                  detail: persianDigits('۳٫۲ مگابایت'),
                  onTap: () {},
                  trailing: IconButton(
                    tooltip: 'اقدامات آهنگ',
                    onPressed: () {},
                    icon: const Icon(NafirIcons.dotsThreeVertical),
                  ),
                ),
                NafirTrackRow(
                  seed: 'gallery-2',
                  title: 'Now playing',
                  subtitle: 'Artist',
                  active: true,
                  onTap: () {},
                ),
                const NafirSectionHeader(title: 'حالت‌ها'),
                const SizedBox(
                  height: 280,
                  child: NafirStateView(
                    icon: NafirIcons.musicNotes,
                    title: 'کتابخانهٔ شما خالی است',
                    message: 'با «افزودن موسیقی» اولین آهنگ را اضافه کنید.',
                  ),
                ),
                SizedBox(
                  height: 300,
                  child: NafirStateView.error(
                    icon: NafirIcons.cloudSlash,
                    title: 'کتابخانه دریافت نشد',
                    message: 'اتصال اینترنت را بررسی کنید.',
                    action: FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(NafirIcons.arrowsClockwise),
                      label: const Text('تلاش دوباره'),
                    ),
                  ),
                ),
                const SizedBox(
                  height: 200,
                  child: NafirStateView.loading(title: 'در حال بارگذاری…'),
                ),
                const NafirSectionHeader(title: 'برگه و گفت‌وگو'),
                _Wrap(children: [
                  OutlinedButton(
                    onPressed: () => showNafirSheet<void>(
                      context,
                      builder: (_) => NafirSheetFrame(
                        title: 'برگهٔ نمونه',
                        child: ListView(
                          padding: nafirListBottomPadding(context),
                          children: [
                            for (var i = 1; i <= 12; i++)
                              NafirTrackRow(
                                seed: 'sheet-$i',
                                title: 'آهنگ ${persianDigits(i)}',
                                subtitle: 'هنرمند',
                              ),
                          ],
                        ),
                      ),
                    ),
                    child: const Text('باز کردن برگه'),
                  ),
                  OutlinedButton(
                    onPressed: () => showNafirConfirm(
                      context,
                      title: 'حذف فهرست پخش؟',
                      message: 'آهنگ‌های کتابخانه حذف نمی‌شوند.',
                      confirmLabel: 'حذف',
                      destructive: true,
                    ),
                    child: const Text('گفت‌وگوی تأیید'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Wrap extends StatelessWidget {
  const _Wrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: NafirSpace.xxl, vertical: NafirSpace.sm),
        child: Wrap(
          spacing: NafirSpace.md,
          runSpacing: NafirSpace.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: color,
              borderRadius: NafirRadii.control,
              border: Border.all(color: NafirColors.softBorder),
            ),
          ),
          const SizedBox(height: NafirSpace.xs),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _Measure extends StatelessWidget {
  const _Measure({
    required this.label,
    required this.value,
    this.width,
    this.radius,
  });

  final String label;
  final double value;
  final double? width;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: width ?? 56,
          height: radius == null ? 16 : 56,
          decoration: BoxDecoration(
            color: radius == null ? colors.primary : colors.secondaryContainer,
            borderRadius: BorderRadius.circular(radius ?? NafirRadii.xs / 2),
          ),
        ),
        const SizedBox(height: NafirSpace.xs),
        Text('$label ${persianDigits(value.round())}',
            style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
