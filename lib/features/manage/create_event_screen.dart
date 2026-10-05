import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/category_dropdown.dart';
import 'package:sportpadi_mobile/shared/widgets/event_audience.dart';
import 'package:sportpadi_mobile/shared/widgets/event_reminders.dart';
import 'package:sportpadi_mobile/shared/widgets/event_spots.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen(
      {super.key, required this.groupId, this.initialTeamIds = const []});
  final String groupId;

  /// Open as a team event for these teams (e.g. from a team page).
  final List<String> initialTeamIds;
  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  String? _categoryId;
  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;
  bool _private = false;
  // Spots: a cap on players and whether an RSVP holds a spot.
  final _maxPlayers = TextEditingController();
  String _rsvpPolicy = 'open';
  bool _busy = false;

  /// Reminder schedule — the default (2 days + 2 hours before) until changed.
  Set<String> _reminders = {...kDefaultReminderSlots};
  String? _error;

  /// "Who's it for?" — null until the audience options load (then: team
  /// event when preselected, or when the viewer can't make group events).
  bool? _forTeams;
  late final Set<String> _teamIds = {...widget.initialTeamIds};

  @override
  void dispose() {
    _title.dispose();
    _maxPlayers.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(() => _error = 'Pick a sport');
      return;
    }
    if (_date == null) {
      setState(() => _error = 'Pick a date');
      return;
    }
    // The venue pins the event to its own timezone — required.
    if (_location.text.trim().isEmpty) {
      setState(() => _error =
          'Add the venue (street/park and city) so players can find it.');
      return;
    }
    final options =
        ref.read(eventAudiencesProvider(widget.groupId)).valueOrNull;
    final forTeams = _isForTeams(options);
    // Only teams this viewer may pick (a stale preselection is dropped).
    final teamIds = forTeams
        ? [
            for (final id in _teamIds)
              if (options == null || options.hasTeam(id)) id
          ]
        : const <String>[];
    if (forTeams && teamIds.isEmpty) {
      setState(() => _error = 'Pick the team this event is for');
      return;
    }
    // The screen can be popped mid-save: invalidate through the container,
    // never `ref` after an await.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(manageRepositoryProvider).createEvent({
        'title': _title.text.trim(),
        'categoryId': _categoryId,
        'groupId': widget.groupId,
        'eventDate': DateTime.utc(_date!.year, _date!.month, _date!.day)
            .toIso8601String(),
        'locationName':
            _location.text.trim().isEmpty ? null : _location.text.trim(),
        'description':
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        'startTime': _start != null ? _hhmm(_start!) : null,
        'endTime': _end != null ? _hhmm(_end!) : null,
        'visibility': _private ? 'private' : 'public',
        if (int.tryParse(_maxPlayers.text.trim()) != null)
          'maxPlayers': int.parse(_maxPlayers.text.trim()),
        if (_rsvpPolicy != 'open') 'rsvpPolicy': _rsvpPolicy,
        if (teamIds.isNotEmpty) 'teamIds': teamIds,
        // Omitted = the server default; [] = no reminders.
        if (!sameReminderSlots(_reminders, kDefaultReminderSlots))
          'reminders': orderReminderSlots(_reminders),
      });
      container.invalidate(groupEventsProvider(widget.groupId));
      container.invalidate(discoverProvider);
      container.invalidate(myFeedProvider);
      final slug = res['slug'];
      if (!mounted) return;
      if (teamIds.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('The team has been notified')));
      }
      if (slug is String && slug.isNotEmpty) {
        context.pushReplacement('/events/$slug');
      } else {
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Team event? Coaches who can't make group events always pick a team.
  /// No options at all (not staff here) → the plain group event; the server
  /// has the final say.
  bool _isForTeams(EventAudienceOptions? o) {
    if (o != null && !o.canCreate) return false;
    if (o != null && !o.canGeneral) return true;
    return _forTeams ?? widget.initialTeamIds.isNotEmpty;
  }

  void _toggleTeam(String id, EventAudienceOptions o) {
    setState(() {
      if (!_teamIds.remove(id)) _teamIds.add(id);
      // A single team picked → default the sport to the team's.
      if (_categoryId == null && _teamIds.length == 1) {
        final teamCat = o.teams
            .where((t) => t.id == _teamIds.first)
            .map((t) => t.categoryId)
            .firstOrNull;
        final known = ref.read(categoriesProvider).valueOrNull;
        if (teamCat != null &&
            known != null &&
            known.any((c) => c.id == teamCat)) {
          _categoryId = teamCat;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final options = ref.watch(eventAudiencesProvider(widget.groupId));
    final groupName =
        ref.watch(groupProvider(widget.groupId)).valueOrNull?.name;
    final o = options.valueOrNull;
    final forTeams = _isForTeams(o);
    return Scaffold(
      appBar:
          AppBar(leading: const SpLeading(), title: const Text('New event')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (options.isLoading && o == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (o != null && o.canCreate) ...[
              EventAudiencePicker(
                groupName: groupName,
                teams: o.teams,
                allowEveryone: o.canGeneral,
                forTeams: forTeams,
                selected: _teamIds,
                isPrivate: _private,
                onForTeamsChanged: (v) => setState(() => _forTeams = v),
                onToggleTeam: (id) => _toggleTeam(id, o),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Add a title' : null,
            ),
            const SizedBox(height: 14),
            CategoryDropdown(
                value: _categoryId,
                onChanged: (v) => setState(() => _categoryId = v)),
            const SizedBox(height: 14),
            _PickerTile(
              label: 'Date',
              value: _date == null
                  ? 'Choose'
                  : DateFormat('EEE, d MMM yyyy').format(_date!),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date ?? now,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 3),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            Row(children: [
              Expanded(
                child: _PickerTile(
                  label: 'Start',
                  value: _start == null ? 'Optional' : _start!.format(context),
                  onTap: () async {
                    final t = await showTimePicker(
                        context: context,
                        initialTime: _start ?? TimeOfDay.now());
                    if (t != null) setState(() => _start = t);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PickerTile(
                  label: 'End',
                  value: _end == null ? 'Optional' : _end!.format(context),
                  onTap: () async {
                    final t = await showTimePicker(
                        context: context, initialTime: _end ?? TimeOfDay.now());
                    if (t != null) setState(() => _end = t);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextFormField(
              controller: _location,
              decoration:
                  const InputDecoration(labelText: 'Location (optional)'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration:
                  const InputDecoration(labelText: 'Description (optional)'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Private event'),
              subtitle: Text(
                  forTeams
                      ? teamEventHint(isPrivate: true)
                      : 'Only your group can see it',
                  style: TextStyle(color: p.muted, fontSize: 12)),
              value: _private,
              onChanged: (v) => setState(() => _private = v),
            ),
            const SizedBox(height: 10),
            EventSpotsPicker(
              maxPlayers: _maxPlayers,
              rsvpPolicy: _rsvpPolicy,
              enabled: !_busy,
              onMaxPlayers: (_) => setState(() {}),
              onRsvpPolicy: (v) => setState(() => _rsvpPolicy = v),
            ),
            const SizedBox(height: 10),
            EventRemindersPicker(
              selected: _reminders,
              enabled: !_busy,
              onChanged: (v) => setState(() => _reminders = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Create event'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Text(value, style: TextStyle(color: p.ink)),
        ),
      ),
    );
  }
}
