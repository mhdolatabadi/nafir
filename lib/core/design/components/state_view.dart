import 'package:flutter/material.dart';
import 'package:nafir/core/design/tokens.dart';

/// One centred message for a state with nothing else to show: an empty
/// list, a failure, or content still on its way. Every screen uses it, so
/// these moments look and read the same everywhere.
class NafirStateView extends StatelessWidget {
  const NafirStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = NafirStateTone.neutral,
  }) : loading = false;

  /// A failure: names the problem in [title] and the way out in [message]
  /// or [action].
  const NafirStateView.error({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  })  : tone = NafirStateTone.error,
        loading = false;

  /// Content on its way. [title] is read out by screen readers and shown
  /// under the indicator.
  const NafirStateView.loading({super.key, required this.title, this.message})
      : icon = null,
        action = null,
        tone = NafirStateTone.neutral,
        loading = true;

  final IconData? icon;
  final String title;
  final String? message;

  /// Usually one button, with at least a 48 px target.
  final Widget? action;
  final NafirStateTone tone;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final error = tone == NafirStateTone.error;
    final badge = loading
        ? const SizedBox.square(
            dimension: 40,
            child: CircularProgressIndicator(strokeWidth: 3),
          )
        : Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: error ? colors.errorContainer : colors.secondaryContainer,
              borderRadius: NafirRadii.panel,
            ),
            child: Icon(
              icon,
              size: 36,
              color:
                  error ? colors.onErrorContainer : colors.onSecondaryContainer,
            ),
          );
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            NafirSpace.xxl,
            NafirSpace.xxl,
            NafirSpace.xxl,
            MediaQuery.viewPaddingOf(context).bottom + NafirSpace.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Semantics(
            liveRegion: loading || error,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(child: badge),
                const SizedBox(height: NafirSpace.xl),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: (loading
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.titleLarge)
                      ?.copyWith(color: colors.onSurface),
                ),
                if (message != null) ...[
                  const SizedBox(height: NafirSpace.sm),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: NafirSpace.xl),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum NafirStateTone { neutral, error }
