import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/category_dropdown.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

class CreateTournamentScreen extends ConsumerStatefulWidget {
  const CreateTournamentScreen({super.key, required this.groupId});
  final String groupId;
  @override
  ConsumerState<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends ConsumerState<CreateTournamentScreen> {
  final _title = TextEditingController();
  final _search = TextEditingController();
  final _fee = TextEditingController();
  String? _categoryId;
  DateTime? _date;
  String _mode = 'friendly';
  String? _hostTeamId;
  final List<TeamSummary> _guests = [];
  int _maxTeams = 8;

  List<TeamSummary> _results = const [];
  bool _searching = false;
  int _searchToken = 0;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _search.dispose();
    _fee.dispose();
    super.dispose();
  }

  bool get _isMulti => _mode != 'friendly';

  int? _feeMinor() {
    final wallet = ref.read(groupWalletProvider(widget.groupId)).valueOrNull;
    if (wallet == null || !wallet.active) return null;
    final v = double.tryParse(_fee.text.trim());
    if (v == null || v <= 0) return null;
    var mult = 1;
    for (var i = 0; i < wallet.exponent; i++) {
      mult *= 10;
    }
    return (v * mult).round();
  }

  Future<void> _runSearch(String q) async {
    if (_categoryId == null || q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    final token = ++_searchToken;
    setState(() => _searching = true);
    try {
      final res = await ref.read(manageRepositoryProvider).searchTeams(
            q.trim(),
            categoryId: _categoryId,
            excludeGroupId: widget.groupId,
          );
      if (token == _searchToken && mounted) {
        setState(() => _results = res);
      }
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted && token == _searchToken) setState(() => _searching = false);
    }
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) return setState(() => _error = 'Add a title');
    if (_categoryId == null) return setState(() => _error = 'Pick a sport');
    if (_date == null) return setState(() => _error = 'Pick a date');
    if (_hostTeamId == null) return setState(() => _error = 'Choose your team');
    if (!_isMulti && _guests.isEmpty) return setState(() => _error = 'Invite an opponent');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(manageRepositoryProvider).createTournament({
        'groupId': widget.groupId,
        'categoryId': _categoryId,
        'title': _title.text.trim(),
        'mode': _mode,
        'eventDate': DateTime.utc(_date!.year, _date!.month, _date!.day).toIso8601String(),
        'hostTeamId': _hostTeamId,
        'guestTeamId': _isMulti ? null : _guests.first.id,
        'guestTeamIds': _isMulti ? _guests.map((g) => g.id).toList() : null,
        'maxTeams': _isMulti ? _maxTeams : null,
        'feeMinor': _feeMinor(),
      });
      ref.invalidate(groupTournamentsProvider(widget.groupId));
      final eventId = res['eventId'];
      if (!mounted) return;
      if (eventId is String && eventId.isNotEmpty) {
        context.pushReplacement('/tournaments/$eventId');
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
    final teams = ref.watch(groupTeamsProvider(widget.groupId));
    final hostTeams = teams.maybeWhen(
      data: (list) => list.where((t) => _categoryId == null || t.categoryId == _categoryId).toList(),
      orElse: () => const <TeamSummary>[],
    );
    return Scaffold(
      appBar: AppBar(leading: const SpLeading(), title: const Text('New tournament')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 14),
          CategoryDropdown(
            value: _categoryId,
            onChanged: (v) => setState(() {
              _categoryId = v;
              _hostTeamId = null;
              _guests.clear();
              _results = const [];
            }),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _date ?? now,
                firstDate: now,
                lastDate: DateTime(now.year + 3),
              );
              if (d != null) setState(() => _date = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date'),
              child: Text(_date == null ? 'Choose' : DateFormat('EEE, d MMM yyyy').format(_date!)),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'friendly', label: Text('Friendly')),
              ButtonSegment(value: 'multi_team', label: Text('Multi-team')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              _guests.clear();
            }),
          ),
          const SizedBox(height: 16),
          Text('Your team (host)', style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 6),
          if (_categoryId == null)
            Text('Pick a sport first.', style: TextStyle(color: p.muted, fontSize: 13))
          else if (hostTeams.isEmpty)
            Text('You have no team for this sport yet.',
                style: TextStyle(color: p.muted, fontSize: 13))
          else
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Host team'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _hostTeamId,
                  isExpanded: true,
                  isDense: true,
                  hint: const Text('Choose your team'),
                  items: [
                    for (final t in hostTeams)
                      DropdownMenuItem(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: (v) => setState(() => _hostTeamId = v),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(_isMulti ? 'Invite teams' : 'Opponent team',
              style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 6),
          if (_guests.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in _guests)
                  Chip(
                    label: Text(g.name),
                    onDeleted: () => setState(() => _guests.remove(g)),
                  ),
              ],
            ),
          const SizedBox(height: 6),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Search team @handle or name',
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : const Icon(Icons.search_rounded),
            ),
            onChanged: _runSearch,
          ),
          for (final r in _results.where((r) => !_guests.any((g) => g.id == r.id)))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Crest(
                  logoUrl: r.logoUrl,
                  kitPrimary: r.kitPrimary,
                  kitSecondary: r.kitSecondary,
                  label: r.name,
                  size: 36),
              title: Text(r.name),
              subtitle: r.username != null ? Text('@${r.username}') : null,
              trailing: const Icon(Icons.add_rounded),
              onTap: () => setState(() {
                if (_isMulti) {
                  if (1 + _guests.length < _maxTeams) _guests.add(r);
                } else {
                  _guests
                    ..clear()
                    ..add(r);
                }
                _search.clear();
                _results = const [];
              }),
            ),
          if (_isMulti) ...[
            const SizedBox(height: 12),
            Row(children: [
              Text('Max teams', style: TextStyle(color: p.muted, fontSize: 12)),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => _maxTeams = (_maxTeams - 1).clamp(2, 32)),
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              Text('$_maxTeams', style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: () => setState(() => _maxTeams = (_maxTeams + 1).clamp(2, 32)),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ]),
          ],
          Builder(builder: (context) {
            final wallet = ref.watch(groupWalletProvider(widget.groupId)).valueOrNull;
            if (wallet == null || !wallet.active) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextField(
                controller: _fee,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Entry fee (optional)',
                  prefixText: '${wallet.currency ?? ''} ',
                  helperText: 'Invited teams pay this into your group wallet.',
                ),
              ),
            );
          }),
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
                : const Text('Create & invite'),
          ),
        ],
      ),
    );
  }
}
