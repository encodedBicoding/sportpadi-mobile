import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// A small ⓘ that explains a term on tap (the mobile twin of the web
/// `InfoTip`). Keep copy to one or two plain sentences.
class SpInfoTip extends StatelessWidget {
  const SpInfoTip(this.text, {super.key, this.size = 14, this.color});
  final String text;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: text,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 7),
      preferBelow: false,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.ink,
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: TextStyle(color: p.bg, fontSize: 12.5, height: 1.4),
      child: Padding(
        // Generous hit area without changing the visual size.
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.info_outline_rounded,
            size: size, color: color ?? p.muted.withAlpha(200)),
      ),
    );
  }
}

/// Text followed by an ⓘ, for labels and section titles.
class TipText extends StatelessWidget {
  const TipText(this.text,
      {super.key, required this.style, this.tip, this.maxLines});
  final String text;
  final TextStyle style;
  final String? tip;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    if (tip == null) {
      return Text(text,
          style: style,
          maxLines: maxLines,
          overflow: maxLines != null ? TextOverflow.ellipsis : null);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(text,
            style: style,
            maxLines: maxLines,
            overflow: maxLines != null ? TextOverflow.ellipsis : null),
      ),
      SpInfoTip(tip!, size: (style.fontSize ?? 12) + 2, color: style.color),
    ]);
  }
}
