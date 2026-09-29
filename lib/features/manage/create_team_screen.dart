import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/category_dropdown.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

/// Kit colours a team can pick from. The web form takes any hex through a
/// colour input; on a phone a palette is quicker and every one of these reads
/// well as a crest. Both sides store the same `#rrggbb`.
const _kitPalette = <String>[
  '#16a34a', // green (default, brand)
  '#dc2626', // red
  '#2563eb', // blue
  '#0ea5e9', // sky
  '#f59e0b', // amber
  '#eab308', // yellow
  '#f97316', // orange
  '#7c3aed', // purple
  '#db2777', // pink
  '#0d9488', // teal
  '#111827', // black
  '#ffffff', // white
  '#6b7280', // grey
  '#7f1d1d', // maroon
  '#1e3a8a', // navy
];

class CreateTeamScreen extends ConsumerStatefulWidget {
  const CreateTeamScreen({super.key, required this.groupId, this.categoryId});
  final String groupId;

  /// Pre-selects the sport — the group Teams tab passes it when you add a
  /// team from under a sport's heading.
  final String? categoryId;
  @override
  ConsumerState<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends ConsumerState<CreateTeamScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _venue = TextEditingController();
  final _description = TextEditingController();
  late String? _categoryId = widget.categoryId;
  // Same defaults as the web form: green shirt, white trim.
  String _kitPrimary = '#16a34a';
  String _kitSecondary = '#ffffff';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(() => _error = 'Pick a sport');
      return;
    }
    // Same rule as the server (plan OR promo code): no second team in a
    // sport on a one-team-per-sport plan.
    final allow = ref.read(teamAllowanceProvider(widget.groupId)).valueOrNull;
    if (allow != null && !allow.canAddTo(_categoryId!)) {
      setState(() => _error = allow.canBuild
          ? 'Your plan allows one team per sport. Upgrade, or redeem a promo code with Build Multiple Teams, to add more.'
          : "Your group's plan doesn't include building teams. Upgrade to unlock it.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(manageRepositoryProvider).createTeam(widget.groupId, {
        'categoryId': _categoryId,
        'name': _name.text.trim(),
        'kitPrimary': _kitPrimary,
        'kitSecondary': _kitSecondary,
        'homeVenue': _venue.text.trim().isEmpty ? null : _venue.text.trim(),
        'description':
            _description.text.trim().isEmpty ? null : _description.text.trim(),
      });
      ref.invalidate(groupTeamsProvider(widget.groupId));
      ref.invalidate(teamAllowanceProvider(widget.groupId));
      final id = res['id'];
      if (!mounted) return;
      if (id is String && id.isNotEmpty) {
        context.pushReplacement('/teams/$id');
      } else {
        context.pop();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(leading: const SpLeading(), title: const Text('New team')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Team name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Add a name' : null,
            ),
            const SizedBox(height: 14),
            Builder(builder: (context) {
              final allow =
                  ref.watch(teamAllowanceProvider(widget.groupId)).valueOrNull;
              // One-team-per-sport plans: sports with a team are off the menu.
              final taken = allow == null || allow.canBuildMultiple
                  ? const <String>{}
                  : allow.takenCategoryIds;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategoryDropdown(
                    value: _categoryId,
                    disabledIds: taken,
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  if (taken.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Your plan allows one team per sport, so sports that already have a team are greyed out. Upgrade, or redeem a promo code with Build Multiple Teams, to add more.',
                      style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
                    ),
                  ],
                ],
              );
            }),
            const SizedBox(height: 18),
            // Kit — what the crest will look like everywhere the team appears.
            Row(children: [
              Crest(
                label: _name.text.trim().isEmpty ? 'T' : _name.text.trim(),
                kitPrimary: _kitPrimary,
                kitSecondary: _kitSecondary,
                size: 56,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kit colours',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('Shirt and trim — this is the crest on every team sheet.',
                          style: TextStyle(color: p.muted, fontSize: 11.5)),
                    ]),
              ),
            ]),
            const SizedBox(height: 10),
            _KitPicker(
              label: 'Primary',
              value: _kitPrimary,
              onChanged: (v) => setState(() => _kitPrimary = v),
            ),
            const SizedBox(height: 8),
            _KitPicker(
              label: 'Secondary',
              value: _kitSecondary,
              onChanged: (v) => setState(() => _kitSecondary = v),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _venue,
              decoration: const InputDecoration(labelText: 'Home venue (optional)'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create team'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of kit swatches with the chosen one ringed.
class _KitPicker extends StatelessWidget {
  const _KitPicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  Color _color(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 76,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(label,
              style: TextStyle(
                  color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
      Expanded(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hex in _kitPalette)
              InkWell(
                onTap: () => onChanged(hex),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _color(hex),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hex.toLowerCase() == value.toLowerCase()
                          ? p.accent
                          : p.line,
                      width: hex.toLowerCase() == value.toLowerCase() ? 3 : 1,
                    ),
                  ),
                  child: hex.toLowerCase() == value.toLowerCase()
                      ? Icon(Icons.check_rounded,
                          size: 16,
                          color: hex == '#ffffff' || hex == '#eab308'
                              ? Colors.black87
                              : Colors.white)
                      : null,
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}
