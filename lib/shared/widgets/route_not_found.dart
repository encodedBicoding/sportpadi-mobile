import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';

/// What a path with no screen in the app shows (the router's `errorBuilder`).
///
/// go_router's own fallback is a bare "Page Not Found" with the exception
/// text and a button to `/` (the splash): it reads as the app breaking. A
/// tap that pushes a path the router doesn't know (the profile's team chip
/// did, with the web's `/groups/<g>/teams/<t>`) lands here instead — the
/// page's honest title, why, and the way out SpHeader always offers (back
/// when there is history, otherwise Home).
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
          children: [
            SpHeader(title: context.l10n.common_pageNotFound),
            const SizedBox(height: 48),
            Icon(Icons.link_off_rounded, color: p.muted, size: 40),
            const SizedBox(height: 12),
            Text(context.l10n.common_thePageYoureLookingFor,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 14, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
