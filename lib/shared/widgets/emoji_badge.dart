import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

class EmojiBadge extends StatelessWidget {
  const EmojiBadge({super.key, this.emoji, this.size = 44});
  final String? emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.line),
      ),
      child: Text(emoji ?? '🏆', style: TextStyle(fontSize: size * 0.44)),
    );
  }
}
