import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// The 2026 pushed-screen header: a round back button, a bold title with an
/// optional subtitle, and optional round actions on the right. Replaces the
/// plain AppBar on redesigned screens; lives inside the scroll view so it
/// scrolls away with the content.
///
/// Back behaves like [SpLeading]: pop when there's history, otherwise a Home
/// button so a screen opened from a link never strands the user.
class SpHeader extends StatelessWidget {
  const SpHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canPop = context.canPop() || Navigator.of(context).canPop();
    return Row(children: [
      SpRoundButton(
        icon: canPop ? Icons.arrow_back_ios_new_rounded : Icons.home_outlined,
        tooltip: canPop ? 'Back' : 'Home',
        iconSize: canPop ? 18 : 21,
        onTap: () {
          if (context.canPop()) {
            context.pop();
          } else if (Navigator.of(context).canPop()) {
            Navigator.of(context).maybePop();
          } else {
            context.go('/home');
          }
        },
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w800)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
      ),
      for (final a in actions) ...[const SizedBox(width: 8), a],
    ]);
  }
}

/// A 44px round surface button — the header's back and action buttons.
class SpRoundButton extends StatelessWidget {
  const SpRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.iconSize = 20,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final button = Material(
      color: p.surface,
      shape: CircleBorder(
          side: dark ? BorderSide(color: p.line) : BorderSide.none),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: iconSize, color: p.ink),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
