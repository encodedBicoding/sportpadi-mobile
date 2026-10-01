import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';

/// Team events — "Who's it for?" on the create / edit event forms, and the
/// "For U12 Lions" chip on event headers, lists and calendar rows.
///
/// A team event is a normal event aimed at one or more of the group's teams:
/// only that segment (players, their guardians, coaches) is notified and sees
/// it listed; anyone with the link can still open it and check in — unless
/// it's also private, then only the team can open it.

/// The helper line under the team list (and the Private switch subtitle).
String teamEventHint({required bool isPrivate}) => isPrivate
    ? 'Only this team can open it'
    : "Only this team's players, their guardians and coaches are notified "
        'and see it — anyone with the link can still join';

class EventAudiencePicker extends StatelessWidget {
  const EventAudiencePicker({
    super.key,
    required this.groupName,
    required this.teams,
    required this.allowEveryone,
    required this.forTeams,
    required this.selected,
    required this.isPrivate,
    required this.onForTeamsChanged,
    required this.onToggleTeam,
  });

  final String? groupName;
  final List<AudienceTeamOption> teams;

  /// Show "Everyone in <group>" (group admins; coaches only pick teams).
  final bool allowEveryone;
  final bool forTeams;
  final Set<String> selected;
  final bool isPrivate;
  final ValueChanged<bool> onForTeamsChanged;
  final ValueChanged<String> onToggleTeam;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final everyone = groupName == null || groupName!.trim().isEmpty
        ? 'Everyone in the group'
        : 'Everyone in ${groupName!.trim()}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text("Who's it for?",
            style: TextStyle(
                color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (allowEveryone)
          Row(children: [
            Expanded(
              child: _ChoiceCard(
                icon: Icons.groups_outlined,
                label: everyone,
                selected: !forTeams,
                onTap: () => onForTeamsChanged(false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ChoiceCard(
                icon: Icons.shield_outlined,
                label: 'A team',
                selected: forTeams,
                onTap: () => onForTeamsChanged(true),
              ),
            ),
          ]),
        if (forTeams) ...[
          if (allowEveryone) const SizedBox(height: 8),
          if (teams.isEmpty)
            Text(
                'No teams to pick yet — build one from the group\'s Teams tab.',
                style: TextStyle(color: p.muted, fontSize: 12.5))
          else
            for (final t in teams)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _TeamRow(
                  team: t,
                  selected: selected.contains(t.id),
                  onTap: () => onToggleTeam(t.id),
                ),
              ),
          const SizedBox(height: 2),
          Text(teamEventHint(isPrivate: isPrivate),
              style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
        ],
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: selected ? p.accent : p.line),
    );
    return Material(
      color: selected ? p.accentTint : p.surface,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            Icon(icon, size: 18, color: selected ? p.greenText : p.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow(
      {required this.team, required this.selected, required this.onTap});
  final AudienceTeamOption team;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: selected ? p.accent : p.line),
    );
    final players = team.players;
    return Material(
      color: selected ? p.accentTint : p.surface,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          child: Row(children: [
            Crest(logoUrl: team.logoUrl, label: team.name, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  if (players != null)
                    Text('$players player${players == 1 ? '' : 's'}',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ),
            ),
            if (team.isKids) ...[
              const SizedBox(width: 8),
              _Tag('Kids', color: p.wardInk),
            ],
            const SizedBox(width: 10),
            Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected ? p.accent : p.muted),
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(34),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// "For U12 Lions" — the teams a team event is for. Renders nothing for a
/// whole-group event. Styled like [SpBadge], but ellipsizes long names.
class AudienceBadge extends StatelessWidget {
  const AudienceBadge(this.teams, {super.key, this.tone});
  final List<AudienceTeam> teams;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final label = audienceLabel(teams);
    if (label == null) return const SizedBox.shrink();
    final c = tone ?? context.palette.greenText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: c.withAlpha(34),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.shield_outlined, size: 12, color: c),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
