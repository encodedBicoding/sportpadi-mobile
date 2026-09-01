import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// A crest for groups, teams and people. Uses the logo when present, otherwise
/// the team's kit primary colour as a tinted background with initials — the same
/// idea as the web crest.
class Crest extends ConsumerWidget {
  const Crest({
    super.key,
    this.logoUrl,
    this.label,
    this.kitPrimary,
    this.kitSecondary,
    this.size = 44,
  });

  final String? logoUrl;
  final String? label;
  final String? kitPrimary;
  final String? kitSecondary;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final radius = size >= 48 ? 16.0 : 10.0;
    final kit = _hex(kitPrimary);
    final bg = kit ?? p.surface2;
    // A server-relative URL (e.g. "/uploads/…") needs the API origin on
    // mobile — the web serves them same-origin.
    var url = logoUrl;
    if (url != null && url.startsWith('/')) {
      url = '${ref.watch(appConfigProvider).apiBaseUrl}$url';
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.line),
      ),
      child: (url != null && url.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _initials(p, kit),
            )
          : _initials(p, kit),
    );
  }

  Widget _initials(AppPalette p, Color? kit) {
    final t = (label ?? '?').trim();
    final initials =
        t.isEmpty ? '?' : t.substring(0, t.length >= 2 ? 2 : 1).toUpperCase();
    return Text(
      initials,
      style: TextStyle(
        color: kit != null ? Colors.white : p.muted,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.34,
      ),
    );
  }

  static Color? _hex(String? s) {
    if (s == null || s.isEmpty) return null;
    var h = s.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }
}
