import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/verified_badge.dart';

/// The web Groups-tab card: cover banner with the group's logo, then name
/// (+ verification tick), description and member/follower stats.
///
/// Structure deliberately mirrors [EventFeedCard] (InkWell > Column, with all
/// Positioned widgets confined inside the cover's own Stack) — this Flutter's
/// semantics compiler asserts on an outer Stack/Transform in a scrolled list.
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.group, this.onTap});

  final GroupSummary group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = group;
    return Container(
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
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover banner with the logo + optional Member badge.
              SizedBox(
                height: 96,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (g.coverImageUrl != null)
                      CachedNetworkImage(
                        imageUrl: g.coverImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _coverWash(),
                        errorWidget: (_, __, ___) => _coverWash(),
                      )
                    else
                      _coverWash(),
                    Positioned(
                      left: 14,
                      bottom: 10,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: p.surface, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(15, 30, 22, 0.18),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Crest(
                              logoUrl: g.logoUrl, label: g.name, size: 56),
                        ),
                      ),
                    ),
                    if (g.isMember)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(255, 255, 255, 0.9),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: p.accent),
                          ),
                          child: Text(
                            'Member',
                            style: TextStyle(
                                color: p.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Body.
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (g.isVerified) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: 17),
                        ],
                      ],
                    ),
                    if (g.description != null && g.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        g.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.muted, fontSize: 12.5, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _stat(context, Icons.groups_outlined,
                            g.memberCount ?? 0, 'members'),
                        const SizedBox(width: 16),
                        _stat(context, Icons.favorite_border_rounded,
                            g.followerCount ?? 0, 'followers'),
                        const Spacer(),
                        Icon(Icons.chevron_right_rounded,
                            color: p.muted, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverWash() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromRGBO(23, 166, 94, 0.28),
            Color.fromRGBO(23, 166, 94, 0.10),
            Color.fromRGBO(245, 167, 10, 0.16),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, int value, String label) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: p.accent),
        const SizedBox(width: 5),
        Text(
          '$value',
          style: TextStyle(
              color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: p.muted, fontSize: 12.5)),
      ],
    );
  }
}
