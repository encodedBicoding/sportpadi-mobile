import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "#16a34a" → Color, or null for anything unparseable.
Color? kitColor(String? v) {
  if (v == null || v.isEmpty) return null;
  var h = v.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final n = int.tryParse(h, radix: 16);
  return n == null ? null : Color(n);
}

/// The kit as a banner: primary into secondary, falling back to the brand
/// green. A near-white secondary is swapped for a darker primary so the
/// banner never washes out.
Gradient kitGradient(String? primary, String? secondary) {
  final a = kitColor(primary) ?? const Color(0xFF17A65E);
  var b = kitColor(secondary) ?? const Color(0xFF0F7A45);
  if (b.computeLuminance() > 0.85) {
    b = Color.lerp(a, Colors.black, 0.35)!;
  }
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [a, b],
  );
}

/// A team as a grid tile (2026): kit banner with the crest overlapping its
/// edge, name and handle, then squad size and grade.
class TeamTile extends StatelessWidget {
  const TeamTile({super.key, required this.team, this.onTap});
  final TeamSummary team;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = team;
    final kids = t.grade == 'kids';
    return GlassCard(
      onTap: onTap ?? () => context.push('/teams/${t.id}'),
      padding: const EdgeInsets.all(6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 84,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              bottom: 18,
              child: Container(
                decoration: BoxDecoration(
                  gradient: kitGradient(t.kitPrimary, t.kitSecondary),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xEBFFFFFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(kids ? 'Kids' : 'Adults',
                    style: TextStyle(
                        color: kids
                            ? const Color(0xFF9A4308)
                            : const Color(0xFF0E1411),
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.surface, width: 3),
                ),
                child: Crest(
                    logoUrl: t.logoUrl,
                    kitPrimary: t.kitPrimary,
                    kitSecondary: t.kitSecondary,
                    label: t.name,
                    size: 42),
              ),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              if (t.username != null)
                Text('@${t.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              const Spacer(),
              Row(children: [
                Icon(Icons.groups_outlined, size: 14, color: p.greenText),
                const SizedBox(width: 4),
                Text(
                    '${t.memberCount ?? 0} player${(t.memberCount ?? 0) == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: p.greenText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
