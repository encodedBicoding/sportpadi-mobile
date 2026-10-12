import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart' show deviceTimezone;
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Venues of a league season or a multi-team tournament (web
/// `components/venues/VenueManager.tsx`). A venue is pinned once — its time
/// zone comes with it — and fixtures / matches are placed in venues instead
/// of typing a place on each one. The caller wires the API calls.

class VenueItem {
  const VenueItem({
    required this.id,
    required this.name,
    this.address,
    required this.label,
    this.timezone,
    this.notes,
    this.status = 'active',
    this.upcoming = 0,
    this.total = 0,
  });
  final String id;
  final String name;
  final String? address;
  final String label;
  final String? timezone;
  final String? notes;
  final String status;
  final int upcoming;
  final int total;
  bool get active => status == 'active';

  static String? _s(dynamic v) => v == null || '$v'.isEmpty ? null : '$v';
  static int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  factory VenueItem.fromJson(Map<String, dynamic> j) => VenueItem(
        id: '${j['id']}',
        name: _s(j['name']) ?? 'Venue',
        address: _s(j['address']),
        label: _s(j['label']) ?? _s(j['name']) ?? 'Venue',
        timezone: _s(j['timezone']),
        notes: _s(j['notes']),
        status: _s(j['status']) ?? 'active',
        upcoming: _i(j['upcoming']),
        total: _i(j['total']),
      );
}

class VenuesData {
  const VenuesData({this.ready = true, this.venues = const [], this.suggestions = const [], this.unplacedIds = const []});
  final bool ready;
  final List<VenueItem> venues;
  final List<VenueItem> suggestions;
  final List<String> unplacedIds;
  List<VenueItem> get active => venues.where((v) => v.active).toList();

  static List<VenueItem> _list(dynamic v) =>
      v is List ? [for (final x in v) if (x is Map) VenueItem.fromJson(Map<String, dynamic>.from(x))] : const [];

  factory VenuesData.fromJson(Map<String, dynamic> j) => VenuesData(
        ready: j['ready'] != false,
        venues: _list(j['venues']),
        suggestions: _list(j['suggestions']),
        unplacedIds: j['unplacedIds'] is List ? [for (final x in j['unplacedIds'] as List) '$x'] : const [],
      );
}

/// What the panel calls; each may throw (an [ApiException] shows as a snackbar).
class VenueActions {
  const VenueActions({
    required this.add,
    required this.update,
    required this.archive,
    required this.restore,
    required this.placeUnplaced,
  });

  /// body: {name, address, notes} or {fromVenueId}; plus timezone.
  final Future<String?> Function(Map<String, dynamic> body) add;
  final Future<String?> Function(String venueId, Map<String, dynamic> body) update;
  final Future<String?> Function(String venueId, String? moveToVenueId) archive;
  final Future<String?> Function(String venueId) restore;
  final Future<String?> Function(String venueId) placeUnplaced;
}

String pluralNoun(String noun, int n) => n == 1 ? noun : (noun.endsWith('ch') ? '${noun}es' : '${noun}s');

String? _zoneName(String? tz) => tz?.split('/').last.replaceAll('_', ' ');

/// Run an action; snackbar its message (or the error). True when it worked.
Future<bool> runVenueAction(BuildContext context, Future<String?> Function() f) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final msg = await f();
    if (msg != null) messenger.showSnackBar(SnackBar(content: Text(msg)));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Something went wrong.')));
    return false;
  }
}

/// A dropdown of the active venues (with an optional empty choice).
class VenueDropdown extends StatelessWidget {
  const VenueDropdown({super.key, required this.venues, required this.value, required this.onChanged, this.none});
  final List<VenueItem> venues;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Label of the empty choice ("No venue yet", "Keep each fixture's venue"); null = none offered.
  final String? none;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = venues.where((v) => v.active).toList();
    final v = active.any((x) => x.id == value) ? value : null;
    return DropdownButtonFormField<String?>(
      key: ValueKey('venue-${v ?? ''}-${active.length}'),
      initialValue: v ?? (none == null && active.isNotEmpty ? active.first.id : null),
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: p.surface2,
        isDense: true,
        prefixIcon: Icon(Icons.place_rounded, color: p.muted, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
      items: [
        if (none != null) DropdownMenuItem<String?>(value: null, child: Text(none!, style: TextStyle(color: p.muted))),
        for (final x in active)
          DropdownMenuItem<String?>(value: x.id, child: Text(x.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

/// The venue list + add / edit / "no longer available" / restore, and the
/// bar that places everything still without a venue.
class VenuesPanel extends StatelessWidget {
  const VenuesPanel({super.key, required this.data, required this.noun, required this.actions, this.intro});
  final VenuesData data;

  /// "fixture" | "match"
  final String noun;
  final VenueActions actions;
  final String? intro;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = data.active;
    final archived = data.venues.where((v) => !v.active).toList();
    final unplaced = data.unplacedIds.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (intro != null) ...[
        Text(intro!, style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 12),
      ],
      if (unplaced > 0 && active.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.orangeTint, borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            SpIconTile(Icons.wrong_location_rounded, bg: p.surface, fg: p.orangeInk, size: 40, iconSize: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$unplaced ${pluralNoun(noun, unplaced)} without a venue', style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
                Text("They can't go live until placed.", style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
            ),
            SpPill(
              label: 'Place',
              height: 34,
              onTap: () async {
                final id = active.length == 1 ? active.first.id : await pickVenue(context, active, title: 'Place $unplaced ${pluralNoun(noun, unplaced)} in…');
                if (id == null || !context.mounted) return;
                await runVenueAction(context, () => actions.placeUnplaced(id));
              },
            ),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      SpSectionTitle('Venues',
          count: active.length,
          trailing: SpPill(
              label: 'Add venue',
              icon: Icons.add_rounded,
              height: 32,
              onTap: () => showVenueForm(context, noun: noun, suggestions: data.suggestions, firstOne: active.isEmpty, onSubmit: actions.add))),
      const SizedBox(height: 8),
      if (active.isEmpty)
        SpEmpty(
            icon: Icons.place_rounded,
            text: 'Add at least one venue. ${noun == 'fixture' ? 'Fixtures' : 'Matches'} are placed in venues — the first one takes them all, '
                'and its time zone comes with it.')
      else
        for (final v in active) ...[
          _VenueCard(v: v, noun: noun, onTap: () => _venueMenu(context, v)),
          const SizedBox(height: 10),
        ],
      if (archived.isNotEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text('Archived (${archived.length})', style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600)),
            children: [
              for (final v in archived) ...[
                _VenueCard(
                    v: v,
                    noun: noun,
                    onTap: () => runVenueAction(context, () => actions.restore(v.id))),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
    ]);
  }

  Future<void> _venueMenu(BuildContext context, VenueItem v) async {
    final choice = await showSpSheet<String>(context,
        builder: (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SpSheetHeader(title: v.name, subtitle: v.label, icon: Icons.place_rounded),
              ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Edit'), onTap: () => Navigator.pop(c, 'edit')),
              ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: const Text('No longer available…'),
                  subtitle: v.upcoming > 0 ? Text('Move its ${v.upcoming} upcoming ${pluralNoun(noun, v.upcoming)} first') : null,
                  onTap: () => Navigator.pop(c, 'archive')),
            ]));
    if (!context.mounted) return;
    if (choice == 'edit') {
      await showVenueForm(context, noun: noun, initial: v, onSubmit: (body) => actions.update(v.id, body));
    } else if (choice == 'archive') {
      await _archive(context, v);
    }
  }

  Future<void> _archive(BuildContext context, VenueItem v) async {
    final others = data.active.where((x) => x.id != v.id).toList();
    if (v.upcoming == 0) {
      await runVenueAction(context, () => actions.archive(v.id, null));
      return;
    }
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add another venue first, then move these matches there.')));
      return;
    }
    final to = await pickVenue(context, others,
        title: 'Move ${v.upcoming} ${pluralNoun(noun, v.upcoming)} to…', subtitle: '${v.name} is archived; everyone in those matches is told.');
    if (to == null || !context.mounted) return;
    await runVenueAction(context, () => actions.archive(v.id, to));
  }
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({required this.v, required this.noun, required this.onTap});
  final VenueItem v;
  final String noun;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Opacity(
      opacity: v.active ? 1 : 0.7,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: p.accentTint,
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.place_rounded, color: p.greenText, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
                    if (v.address != null && v.address != v.name)
                      Text(v.address!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
                ),
                Icon(v.active ? Icons.more_horiz_rounded : Icons.restore_rounded, color: p.ink),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                SpBadge(v.active ? '${v.upcoming} upcoming ${pluralNoun(noun, v.upcoming)}' : 'Archived — tap to restore',
                    tone: v.active && v.upcoming > 0 ? p.greenText : p.muted),
                if (v.timezone != null) SpBadge(_zoneName(v.timezone)!, icon: Icons.schedule_rounded, tone: p.muted),
                if (v.notes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(v.notes!, style: TextStyle(color: p.muted, fontSize: 12, height: 1.35)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Pick one venue from a list (sheet). Null when dismissed.
Future<String?> pickVenue(BuildContext context, List<VenueItem> venues, {required String title, String? subtitle}) {
  return showSpSheet<String>(context,
      builder: (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SpSheetHeader(title: title, subtitle: subtitle, icon: Icons.place_rounded),
            for (final v in venues)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(v.name),
                subtitle: v.address != null && v.address != v.name ? Text(v.address!) : null,
                onTap: () => Navigator.pop(c, v.id),
              ),
          ]));
}

/// Add (typed or copied from one used before) or edit a venue.
Future<void> showVenueForm(
  BuildContext context, {
  required String noun,
  VenueItem? initial,
  List<VenueItem> suggestions = const [],
  bool firstOne = false,
  required Future<String?> Function(Map<String, dynamic> body) onSubmit,
}) {
  return showSpSheet<void>(context,
      builder: (_) => _VenueForm(noun: noun, initial: initial, suggestions: suggestions, firstOne: firstOne, onSubmit: onSubmit));
}

class _VenueForm extends StatefulWidget {
  const _VenueForm({required this.noun, this.initial, required this.suggestions, required this.firstOne, required this.onSubmit});
  final String noun;
  final VenueItem? initial;
  final List<VenueItem> suggestions;
  final bool firstOne;
  final Future<String?> Function(Map<String, dynamic> body) onSubmit;

  @override
  State<_VenueForm> createState() => _VenueFormState();
}

class _VenueFormState extends State<_VenueForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _address = TextEditingController(text: widget.initial?.address ?? '');
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _go(Map<String, dynamic> body) async {
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final ok = await runVenueAction(context, () => widget.onSubmit({...body, 'timezone': deviceTimezone}));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) nav.pop();
  }

  InputDecoration _deco(String label, String hint) {
    final p = context.palette;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: p.surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final edit = widget.initial != null;
    final n = widget.initial?.upcoming ?? 0;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SpSheetHeader(
        title: edit ? 'Edit venue' : 'Add a venue',
        subtitle: edit
            ? (n > 0
                ? '$n ${pluralNoun(widget.noun, n)} ${n == 1 ? 'is' : 'are'} here — they follow this change, and everyone in them is told.'
                : 'Nothing upcoming is played here yet.')
            : widget.firstOne
                ? 'The first venue takes every ${widget.noun} that doesn\'t have one.'
                : 'Pick one you\'ve used before, or add a new one.',
        icon: Icons.place_rounded,
      ),
      if (!edit && widget.suggestions.isNotEmpty) ...[
        Text('USED BEFORE — ONE TAP', style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in widget.suggestions)
            ActionChip(
              avatar: Icon(Icons.add_rounded, size: 16, color: p.greenText),
              label: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              onPressed: _busy ? null : () => _go({'fromVenueId': s.id}),
            ),
        ]),
        const SizedBox(height: 12),
        Text('OR A NEW ONE', style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        const SizedBox(height: 8),
      ],
      TextField(controller: _name, maxLength: 120, onChanged: (_) => setState(() {}), decoration: _deco('Name', 'Burnaby Lake — Pitch 2')),
      const SizedBox(height: 4),
      TextField(controller: _address, maxLength: 200, decoration: _deco('Address', '3500 Sprott St, Burnaby BC')),
      Text('We pin it on the map once — it sets the local time zone for every match played there. Leave it empty to use the name.',
          style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.35)),
      const SizedBox(height: 10),
      TextField(controller: _notes, maxLength: 300, maxLines: 2, decoration: _deco('Notes (optional)', 'Parking on Sprott St · north gate')),
      const SizedBox(height: 8),
      SpButton(
        label: _busy ? 'Saving…' : (edit ? 'Save venue' : 'Add venue'),
        icon: Icons.place_rounded,
        expand: true,
        onTap: _busy || _name.text.trim().isEmpty
            ? null
            : () => _go({
                  'name': _name.text.trim(),
                  'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
                  'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                }),
      ),
    ]);
  }
}
