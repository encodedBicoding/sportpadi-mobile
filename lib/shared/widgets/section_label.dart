import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// Uppercase, tracked section label — mirrors the web's display-heading style.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                color: p.muted,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
