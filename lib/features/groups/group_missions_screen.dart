import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

Map<String, String> get _kindLabel => <String, String>{
  'checkin': l10n.group_missionKindCheckins,
  'checkin_early': l10n.group_missionKindEarlyCheckins,
  'rsvp': l10n.group_missionKindRsvps,
  'game_completed': l10n.group_missionKindGamesCompleted,
  'game_won': l10n.group_wins,
  'new_teammate': l10n.group_missionKindNewTeammates,
  'new_venue': l10n.group_missionKindNewVenues,
  'new_group': l10n.group_missionKindNewGroups,
  'last_minute': l10n.group_missionKindLastMinute,
  'brought_rsvp': l10n.group_missionKindBroughtRsvps,
  'stat': l10n.group_missionKindRecordedStats,
};

/// Group admins publish time-boxed missions to their members and followers
/// — the lever for filling games and bringing people back. Counted only for
/// activity in THIS group's events. Web twin: app/groups/[id]/missions.
class GroupMissionsScreen extends ConsumerStatefulWidget {
  const GroupMissionsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupMissionsScreen> createState() => _GroupMissionsScreenState();
}

class _GroupMissionsScreenState extends ConsumerState<GroupMissionsScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _ruleKind = 'brought_rsvp';
  int _target = 2;
  int _xp = 100;
  int _days = 7;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _applyPreset(MissionPreset p) => setState(() {
        _title.text = p.title;
        _description.text = p.description;
        _ruleKind = p.ruleKind;
        _target = p.target;
        _xp = p.xp;
      });

  Future<void> _publish() async {
    if (_title.text.trim().length < 3) return _snack(l10n.group_giveTheMissionATitle);
    setState(() => _busy = true);
    try {
      await ref.read(progressionRepositoryProvider).createMission(widget.groupId, {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'ruleKind': _ruleKind,
        'target': _target,
        'xp': _xp,
        'days': _days,
      });
      ref.invalidate(groupMissionsProvider(widget.groupId));
      _title.clear();
      _description.clear();
      _snack(l10n.group_missionPublishedToYourPlayers);
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end(GroupMission m) async {
    try {
      await ref.read(progressionRepositoryProvider).archiveMission(widget.groupId, m.key);
      ref.invalidate(groupMissionsProvider(widget.groupId));
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final data = ref.watch(groupMissionsProvider(widget.groupId));
    return SpSubPage(
      title: context.l10n.group_missions,
      subtitle: context.l10n.group_goalsForYourPlayers,
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(groupMissionsProvider(widget.groupId)),
        data: (d) => ListView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 32 + MediaQuery.paddingOf(context).bottom),
          children: [
            // Explainer
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.orangeTint, borderRadius: BorderRadius.circular(20)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SpIconTile(Icons.rocket_launch_outlined, bg: p.surface, fg: p.orangeInk, size: 38, iconSize: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      context.l10n.group_aMissionShowsUpIn,
                      style: TextStyle(color: p.orangeInk, fontSize: 12.5, height: 1.45)),
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // New mission
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SpSectionTitle(context.l10n.group_newMission),
                if (d.presets.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final pr in d.presets)
                      ActionChip(
                        label: Text(pr.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        onPressed: () => _applyPreset(pr),
                        visualDensity: VisualDensity.compact,
                      ),
                  ]),
                ],
                const SizedBox(height: 12),
                TextField(controller: _title, maxLength: 80, decoration: InputDecoration(labelText: context.l10n.group_title, hintText: context.l10n.group_fillTheSquad, counterText: '')),
                const SizedBox(height: 10),
                TextField(controller: _description, maxLength: 240, decoration: InputDecoration(labelText: context.l10n.group_description, counterText: '')),
                const SizedBox(height: 12),
                Text(context.l10n.group_counts, style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: d.kinds.contains(_ruleKind) ? _ruleKind : (d.kinds.isNotEmpty ? d.kinds.first : null),
                  items: [for (final k in d.kinds) DropdownMenuItem(value: k, child: Text(_kindLabel[k] ?? k))],
                  onChanged: (v) => setState(() => _ruleKind = v ?? _ruleKind),
                ),
                const SizedBox(height: 12),
                _Counter(label: context.l10n.group_target, value: _target, min: 1, max: 50, onChanged: (v) => setState(() => _target = v)),
                const SizedBox(height: 8),
                _Counter(label: 'XP', value: _xp, min: 0, max: 500, step: 10, onChanged: (v) => setState(() => _xp = v)),
                const SizedBox(height: 8),
                _Counter(label: context.l10n.group_runsForDays, value: _days, min: 1, max: 90, onChanged: (v) => setState(() => _days = v)),
                const SizedBox(height: 14),
                SpButton(
                  label: _busy ? context.l10n.group_publishing : context.l10n.group_publishMission,
                  expand: true,
                  onTap: _busy || _title.text.trim().length < 3 ? null : _publish,
                ),
              ]),
            ),

            // Your missions
            if (d.missions.isNotEmpty) ...[
              const SizedBox(height: 18),
              SpSectionTitle(context.l10n.group_yourMissions, count: d.missions.length),
              const SizedBox(height: 8),
              SpListCard(children: [
                for (final m in d.missions)
                  Opacity(
                    opacity: m.live ? 1 : 0.6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      child: Row(children: [
                        SpIconTile(Icons.rocket_launch_outlined,
                            bg: m.live ? p.orangeTint : p.surface2, fg: m.live ? p.orangeInk : p.muted, size: 36, iconSize: 17),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                            RichText(
                              text: TextSpan(
                                style: TextStyle(color: p.muted, fontSize: 11.5),
                                children: [
                                  TextSpan(
                                      text: context.l10n.group_xp2(_kindLabel[m.ruleKind] ?? m.ruleKind, m.target, m.xp, m.live ? context.l10n.group_ends(m.endsAt != null ? _day(m.endsAt!) : '—') : context.l10n.group_ended)),
                                  TextSpan(text: context.l10n.group_completed(m.completions), style: TextStyle(color: p.greenText, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ]),
                        ),
                        if (m.live) ...[
                          const SizedBox(width: 8),
                          SpPill(label: context.l10n.group_end, tone: SpPillTone.soft, height: 32, onTap: () => _end(m)),
                        ],
                      ]),
                    ),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  static String _day(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }
}

/// Label + a − / value / + stepper (web: NumberInput).
class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.step = 1});
  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget btn(IconData icon, bool enabled, VoidCallback onTap) => Material(
          color: p.surface2,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 18, color: enabled ? p.ink : p.muted)),
          ),
        );
    return Row(children: [
      Expanded(child: Text(label, style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600))),
      btn(Icons.remove_rounded, value > min, () => onChanged((value - step).clamp(min, max))),
      SizedBox(width: 44, child: Text('$value', textAlign: TextAlign.center, style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800))),
      btn(Icons.add_rounded, value < max, () => onChanged((value + step).clamp(min, max))),
    ]);
  }
}
