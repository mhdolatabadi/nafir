import 'package:flutter/material.dart';
import 'package:nafir/core/design/components/section_header.dart';
import 'package:nafir/core/design/tokens.dart';

/// The inside of a bottom sheet: a heading, optional actions, then the
/// body filling the rest. Pair it with [showNafirSheet].
class NafirSheetFrame extends StatelessWidget {
  const NafirSheetFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Fills the space under the heading; scrollable content should add the
  /// bottom system inset to its own padding.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NafirSectionHeader(
          title: title,
          subtitle: subtitle,
          trailing: trailing,
          padding: const EdgeInsetsDirectional.fromSTEB(
              NafirSpace.xxl, 0, NafirSpace.md, NafirSpace.sm),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Opens a modal sheet [heightFactor] of the screen tall, inside the safe
/// area, with the theme's drag handle.
Future<T?> showNafirSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double heightFactor = 0.75,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: heightFactor,
      child: builder(context),
    ),
  );
}

/// Bottom padding for a scrollable list inside a sheet or page, so its last
/// row clears the gesture bar.
EdgeInsets nafirListBottomPadding(BuildContext context,
        {double extra = NafirSpace.lg}) =>
    EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom + extra);
