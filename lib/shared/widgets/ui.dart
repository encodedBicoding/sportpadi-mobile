import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// The 2026 card: white surface, large radius, soft layered shadow and no
/// hard border (a hairline only in dark mode, where shadows don't read).
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        border: dark ? Border.all(color: p.line) : null,
        boxShadow: cardShadow(context),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap, child: card),
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
          fontWeight: FontWeight.w700,
          letterSpacing: 1.3,
        ),
      );
}

/// Soft tinted pill badge with an optional semantic tone.
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: tone == null ? p.surface2 : c.withAlpha(34),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Icon + text info row (2026): the icon sits in a quiet rounded tile.
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
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: p.surface2, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 17, color: p.greenText),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w500))),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
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

/// Filled pill button built from Material + InkWell. Ink by default (the
/// 2026 primary); `tone: SpButtonTone.brand` for the green one.
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
    this.tone = SpButtonTone.ink,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool expand;
  final SpButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    final bg = tone == SpButtonTone.brand ? p.accentDeep : p.hero;
    final fg = tone == SpButtonTone.brand ? Colors.white : p.onHero;
    return Material(
      color: enabled ? bg : p.surface2,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          // Tighter sides when stretched: an expanded button often shares a
          // row with others, and its label must never push past its edge.
          padding: EdgeInsets.symmetric(
              horizontal: expand ? 12 : 20, vertical: 13),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: enabled ? fg : p.muted),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? fg : p.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum SpButtonTone { ink, brand }

/// One white card of rows separated by hairlines (lists of people, games,
/// notifications, menu items…).
class SpListCard extends StatelessWidget {
  const SpListCard({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
                height: 1,
                thickness: 1,
                indent: 12,
                endIndent: 12,
                color: p.surface2),
          children[i],
        ],
      ]),
    );
  }
}

/// Pill segmented control: a quiet track with the active option on a white
/// thumb.
class SpSegmented extends StatelessWidget {
  const SpSegmented({
    super.key,
    required this.options,
    required this.index,
    required this.onChanged,
    this.icons,
  });
  final List<String> options;
  final List<IconData>? icons;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? p.surface2 : const Color(0xFFE6EBE8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(children: [
        for (var i = 0; i < options.length; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 38,
                decoration: BoxDecoration(
                  color: i == index ? p.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: i == index && !dark
                      ? const [
                          BoxShadow(
                              color: Color(0x140E1411),
                              blurRadius: 2,
                              offset: Offset(0, 1))
                        ]
                      : null,
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icons != null && i < icons!.length) ...[
                        Icon(icons![i],
                            size: 15,
                            color: i == index ? p.ink : p.muted),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(options[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: i == index ? p.ink : p.muted,
                                fontSize: 13,
                                fontWeight: i == index
                                    ? FontWeight.w700
                                    : FontWeight.w600)),
                      ),
                    ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// A section title ("Who's in") with an optional count chip and a trailing
/// link or action.
class SpSectionTitle extends StatelessWidget {
  const SpSectionTitle(this.title, {super.key, this.count, this.trailing});
  final String title;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(children: [
      Flexible(
        child: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: p.ink, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      if (count != null) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: p.surface2, borderRadius: BorderRadius.circular(999)),
          child: Text('$count',
              style: TextStyle(
                  color: p.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ),
      ],
      const Spacer(),
      if (trailing != null) trailing!,
    ]);
  }
}

/// A rounded icon tile (list leads, info rows, menu items).
class SpIconTile extends StatelessWidget {
  const SpIconTile(this.icon,
      {super.key, this.bg, this.fg, this.size = 42, this.iconSize = 20});
  final IconData icon;
  final Color? bg;
  final Color? fg;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg ?? p.surface2,
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(icon, size: iconSize, color: fg ?? p.muted),
    );
  }
}
