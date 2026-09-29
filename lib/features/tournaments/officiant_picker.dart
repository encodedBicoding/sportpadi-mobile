import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// One person picked to officiate.
typedef PickedOfficiant = ({String userId, String label});

/// Multi-select "anyone on SportPadi" search — the same idea as local games,
/// where a match can have any number of officiants. Picked people show as
/// removable chips above a debounced search box.
class OfficiantPicker extends ConsumerStatefulWidget {
  const OfficiantPicker({
    super.key,
    required this.eventId,
    required this.selected,
    required this.onChanged,
    this.exclude = const [],
  });

  final String eventId;
  final List<PickedOfficiant> selected;
  final ValueChanged<List<PickedOfficiant>> onChanged;

  /// User ids already asked (shown elsewhere), hidden from the results.
  final List<String> exclude;

  @override
  ConsumerState<OfficiantPicker> createState() => _OfficiantPickerState();
}

class _OfficiantPickerState extends ConsumerState<OfficiantPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<GroupMemberItem> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (q.trim().length < 2) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      setState(() => _searching = true);
      try {
        final r = await ref
            .read(tournamentsRepositoryProvider)
            .searchOfficiants(widget.eventId, q.trim());
        if (mounted) setState(() => _results = r);
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _add(GroupMemberItem u) {
    final label = u.username != null
        ? '${u.displayName} (@${u.username})'
        : u.displayName;
    widget.onChanged([...widget.selected, (userId: u.userId, label: label)]);
    setState(() {
      _search.clear();
      _results = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final taken = {
      ...widget.exclude,
      for (final s in widget.selected) s.userId,
    };
    final candidates = [
      for (final u in _results)
        if (!taken.contains(u.userId)) u
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.selected.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in widget.selected)
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                  decoration: BoxDecoration(
                    color: p.accent.withAlpha(26),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: p.accent.withAlpha(77)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(s.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => widget.onChanged([
                        for (final x in widget.selected)
                          if (x.userId != s.userId) x
                      ]),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(Icons.close_rounded,
                            size: 14, color: p.muted),
                      ),
                    ),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _search,
          // setState on every keystroke: the results panel is gated on
          // _search.text, so the list must rebuild as the user types.
          onChanged: (v) {
            setState(() {});
            _onSearch(v);
          },
          style: TextStyle(color: p.ink, fontSize: 13.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.selected.isEmpty
                ? 'Search anyone by name or @handle'
                : 'Add another by name or @handle',
            hintStyle: TextStyle(color: p.muted, fontSize: 13),
            prefixIcon: Icon(Icons.search, size: 18, color: p.muted),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: p.line)),
          ),
        ),
        if (_search.text.trim().length >= 2) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 170),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.line),
            ),
            child: candidates.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(_searching ? 'Searching…' : 'No one found.',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final u in candidates)
                        ListTile(
                          dense: true,
                          title: Text(u.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: p.ink, fontSize: 13.5)),
                          subtitle: u.username != null
                              ? Text('@${u.username}',
                                  style: TextStyle(
                                      color: p.muted, fontSize: 11))
                              : null,
                          trailing: Icon(Icons.add_rounded,
                              size: 18, color: p.muted),
                          onTap: () => _add(u),
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

/// Bottom sheet a host admin uses to ask more people to officiate an existing
/// match. Each person gets their own request; the match keeps whoever has
/// already accepted.
class AddOfficiantsSheet extends ConsumerStatefulWidget {
  const AddOfficiantsSheet({
    super.key,
    required this.eventId,
    required this.gameId,
    required this.exclude,
  });

  final String eventId;
  final String gameId;
  final List<String> exclude;

  /// Resolves to true when at least one request was sent.
  static Future<bool> show(BuildContext context,
      {required String eventId,
      required String gameId,
      List<String> exclude = const []}) async {
    final r = await showSpSheet<bool>(
      context,
      builder: (_) => AddOfficiantsSheet(
          eventId: eventId, gameId: gameId, exclude: exclude),
    );
    return r == true;
  }

  @override
  ConsumerState<AddOfficiantsSheet> createState() => _AddOfficiantsSheetState();
}

class _AddOfficiantsSheetState extends ConsumerState<AddOfficiantsSheet> {
  List<PickedOfficiant> _picked = const [];
  bool _saving = false;

  Future<void> _submit() async {
    if (_picked.isEmpty) return;
    setState(() => _saving = true);
    try {
      final added = await ref
          .read(tournamentsRepositoryProvider)
          .addMatchOfficiants(widget.eventId, widget.gameId,
              [for (final s in _picked) s.userId]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(added == 0
              ? 'They were already on the list'
              : 'Asked $added ${added == 1 ? 'person' : 'people'} to officiate')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _picked.length;
    return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SpSheetHeader(
                icon: Icons.sports_rounded,
                title: 'Add officiants',
                subtitle: 'Ask anyone on SportPadi. Each person gets a request and can '
                    'run the match once they accept — have as many as you need.',
              ),
              OfficiantPicker(
                eventId: widget.eventId,
                selected: _picked,
                exclude: widget.exclude,
                onChanged: (v) => setState(() => _picked = v),
              ),
              const SizedBox(height: 16),
              SpButton(
                label: _saving
                    ? 'Sending…'
                    : n == 0
                        ? 'Send requests'
                        : 'Send $n ${n == 1 ? 'request' : 'requests'}',
                expand: true,
                onTap: _saving || n == 0 ? null : _submit,
              ),
            ],
          );
  }
}
