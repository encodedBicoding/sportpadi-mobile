import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Form: the last five results as circles, newest on the right, and the
/// current streak.
class FormStrip extends StatelessWidget {
  const FormStrip({super.key, required this.recent, this.chess = false});

  /// The scope's recent games, newest first.
  final List<Map<String, dynamic>> recent;

  /// Chess marks results by points: 1, ½, 0.
  final bool chess;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final results = formOf(recent).take(5).toList().reversed.toList();
    final streak = streakOf(recent);
    const size = 38.0;

    Color fill(String r) => switch (r) {
          'W' => p.accent,
          'L' => p.danger,
          _ => const Color(0xFF9CA3AF),
        };

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('Form',
                style: TextStyle(
                    color: p.ink, fontSize: 15.5, fontWeight: FontWeight.w700)),
          ),
          if (streak != null)
            MiniChip('Streak $streak', color: streakColor(p, streak)),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          // Empty slots first, so the newest result always sits on the right.
          for (var i = 0; i < 5 - results.length; i++)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: p.line, width: 1.5),
              ),
            ),
          for (var i = 0; i < results.length; i++)
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill(results[i]),
                shape: BoxShape.circle,
                border: i == results.length - 1
                    ? Border.all(color: p.surface, width: 2.5)
                    : null,
                boxShadow: i == results.length - 1
                    ? [
                        BoxShadow(
                            color: fill(results[i]).withAlpha(110),
                            blurRadius: 0,
                            spreadRadius: 2)
                      ]
                    : null,
              ),
              child: Text(chess ? chessMark(results[i]) : results[i],
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900)),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('Older', style: TextStyle(color: p.muted, fontSize: 11)),
          const Spacer(),
          Text('Latest', style: TextStyle(color: p.muted, fontSize: 11)),
        ]),
      ]),
    );
  }
}
