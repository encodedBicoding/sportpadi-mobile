import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The 2026 sub-page frame (web `GroupSubPage`): the round-back [SpHeader]
/// with a title, a "Group · N things" subtitle and pill actions, the body
/// below it, and an optional footer bar pinned to the bottom.
class SpSubPage extends StatelessWidget {
  const SpSubPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.body,
    this.footer,
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: SpHeader(title: title, subtitle: subtitle, actions: actions),
          ),
          Expanded(child: body),
          if (footer != null) footer!,
        ]),
      ),
    );
  }
}

/// A compact pill button (web `SpPill size="sm"`): ink, outline or soft.
enum SpPillTone { ink, outline, soft }

class SpPill extends StatelessWidget {
  const SpPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.tone = SpPillTone.ink,
    this.expand = false,
    this.height = 38,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final SpPillTone tone;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    final (Color bg, Color fg, BorderSide side) = switch (tone) {
      SpPillTone.ink => (p.hero, p.onHero, BorderSide.none),
      SpPillTone.outline => (p.surface, p.ink, BorderSide(color: p.line)),
      SpPillTone.soft => (p.surface2, p.ink, BorderSide.none),
    };
    final shape = StadiumBorder(side: side);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: bg,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: fg,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The search card (web `sp-card h-12 rounded-[18px]`): a white field with a
/// search icon and a clear button once there's text.
class SpSearchCard extends StatelessWidget {
  const SpSearchCard({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onClear,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 16, right: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: dark ? Border.all(color: p.line) : null,
        boxShadow: cardShadow(context),
      ),
      child: Row(children: [
        Icon(Icons.search_rounded, size: 19, color: p.muted),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: p.ink, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: p.muted, fontSize: 14),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (controller.text.isNotEmpty)
          IconButton(
            tooltip: 'Clear search',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
            onPressed: () {
              controller.clear();
              if (onClear != null) {
                onClear!();
              } else {
                onChanged('');
              }
            },
          )
        else
          const SizedBox(width: 10),
      ]),
    );
  }
}

/// The green-tint tip card with a lightbulb (web followers / members tips).
class SpTipCard extends StatelessWidget {
  const SpTipCard(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.accentTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon ?? Icons.lightbulb_outline_rounded,
              size: 17, color: p.greenText),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(color: p.ink, fontSize: 12.5, height: 1.45)),
        ),
      ]),
    );
  }
}

/// The empty state (web `SpEmpty`): a soft icon tile, an optional bold title
/// and a short line, on a card.
class SpEmpty extends StatelessWidget {
  const SpEmpty({super.key, required this.icon, this.title, required this.text});
  final IconData icon;
  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(children: [
        SpIconTile(icon,
            size: 52, iconSize: 24, bg: p.accentTint, fg: p.greenText),
        if (title != null) ...[
          const SizedBox(height: 12),
          Text(title!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
        ],
        SizedBox(height: title != null ? 4 : 12),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.45)),
      ]),
    );
  }
}

/// A round person avatar (web: 44px circle, photo or the initial on a green
/// tint).
class PersonAvatar extends ConsumerWidget {
  const PersonAvatar({super.key, this.url, required this.name, this.size = 44});
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    var src = url;
    // Server-relative uploads need the API origin on mobile.
    if (src != null && src.startsWith('/')) {
      src = '${ref.watch(appConfigProvider).apiBaseUrl}$src';
    }
    final t = name.trim();
    final initial = Text(t.isEmpty ? '?' : t.characters.first.toUpperCase(),
        style: TextStyle(
            color: p.greenText,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700));
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.accentTint, shape: BoxShape.circle),
      child: src != null && src.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: src,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => initial,
            )
          : initial,
    );
  }
}

/// A small uppercase tag (Creator / Admin / Member).
class SpTag extends StatelessWidget {
  const SpTag(this.label, {super.key, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                color: fg,
                fontSize: 10,
                height: 1.3,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w800)),
      );
}
