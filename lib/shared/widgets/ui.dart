import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// The web `.glass` card: soft surface, hairline border, gentle shadow.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.line),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 30, 22, 0.06),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: card),
    );
  }
}

/// Uppercase, wide-tracked eyebrow label.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.palette.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.6,
        ),
      );
}

/// Outline pill badge with an optional semantic tint.
class SpBadge extends StatelessWidget {
  const SpBadge(this.label, {super.key, this.icon, this.tone});
  final String label;
  final IconData? icon;
  final Color? tone;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = tone ?? p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c),
        color: p.surface,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Icon + text info row (web: primary-tinted icon beside a line of detail).
class InfoRow extends StatelessWidget {
  const InfoRow(this.icon, this.text, {super.key, this.trailing});
  final IconData icon;
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 17, color: p.accent),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: p.ink, fontSize: 14))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Gradient banner used as an event / tournament hero (web: primary→sky wash).
class GradientHero extends StatelessWidget {
  const GradientHero({super.key, this.emoji, this.height = 150, this.child});
  final String? emoji;
  final double height;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromRGBO(23, 166, 94, 0.30),
            Color.fromRGBO(23, 166, 94, 0.10),
            Color.fromRGBO(56, 189, 248, 0.22),
          ],
        ),
      ),
      child: child ?? Text(emoji ?? '🏆', style: const TextStyle(fontSize: 52)),
    );
  }
}

/// Filled pill button built from Material + InkWell.
///
/// Deliberately NOT a Material `FilledButton.icon` — that widget's internals
/// trip this Flutter build's semantics compiler with a
/// `!semantics.parentDataDirty` assertion flood (same family as the Badge and
/// offstage-Scaffold crashes we removed). Use this for icon+label buttons.
class SpButton extends StatelessWidget {
  const SpButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    return Material(
      color: enabled ? p.accent : p.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18,
                    color: enabled ? Colors.white : p.muted),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white : p.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
