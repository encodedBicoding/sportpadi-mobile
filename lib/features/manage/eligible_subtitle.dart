import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_models.dart';

/// The line under a member in "Add player" lists: their @handle, a child's
/// age (and, on an "Under N" kids team, that they're over it — a flag, not a
/// block), and for wards that their guardians will be asked.
Widget? eligibleSubtitle(AppPalette p, SimpleUser u, int? ageLimit,
    {bool showHandle = false, bool showWardNote = true}) {
  final parts = <String>[
    if (showHandle && u.username != null) '@${u.username}',
    if (u.age != null)
      u.overAgeLimit && ageLimit != null
          ? '${u.age} yrs · over U$ageLimit'
          : '${u.age} yrs',
    if (showWardNote && u.isWard && !u.invitePending)
      'Their guardians will be asked',
  ];
  if (parts.isEmpty) return null;
  return Text(parts.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          color: u.overAgeLimit ? p.orangeInk : p.muted,
          fontSize: 11.5,
          fontWeight: u.overAgeLimit ? FontWeight.w600 : FontWeight.w400));
}
