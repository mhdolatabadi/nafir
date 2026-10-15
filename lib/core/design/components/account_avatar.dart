import 'package:flutter/material.dart';
import 'package:rhythmo/core/design/tokens.dart';
import 'package:rhythmo/core/widgets/rhythmo_icons.dart';

/// An account shown by its icon alone; the address stays in the tooltip.
/// A verified account carries a blue check at the icon's lower end.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.verified,
    this.size = 24,
  });

  final bool verified;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(RhythmoIcons.userCircle, size: size);
    if (!verified) return icon;
    final badge = size * 0.55;
    return Semantics(
      label: 'حساب تأییدشده',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            icon,
            PositionedDirectional(
              end: -badge * 0.2,
              bottom: -badge * 0.2,
              child: Container(
                key: const ValueKey('verified-badge'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surface,
                ),
                padding: const EdgeInsets.all(1),
                child: Icon(
                  RhythmoIcons.checkCircleFill,
                  size: badge,
                  color: RhythmoColors.verified,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
