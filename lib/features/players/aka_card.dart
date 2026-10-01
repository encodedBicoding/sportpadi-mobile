import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Groups the signed-in player goes by another name in, as `groupId -> aka`.
/// Read on their own profile so each group card can say what it calls them.
final myGroupAkasProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
  try {
    final res = await ref.watch(dioProvider).get('/api/mobile/me/group-aka');
    final list = res.data is List ? res.data as List : const [];
    return {
      for (final e in list)
        if (e is Map &&
            parseStr(e['groupId']) != null &&
            parseStr(e['aka']) != null)
          parseStr(e['groupId'])!: parseStr(e['aka'])!,
    };
  } catch (_) {
    // A nickname is a nicety — never let it break the profile.
    return const <String, String>{};
  }
});

/// Set — or clear — the name you go by in one group.
Future<String?> setGroupAka(WidgetRef ref, String groupId, String? aka) async {
  try {
    final res = await ref.read(dioProvider).post(
      '/api/mobile/me/group-aka',
      data: {'groupId': groupId, 'aka': aka},
    );
    final m = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
    return parseStr(m['aka']);
  } catch (e) {
    throw apiError(e, fallback: 'Could not save that name.');
  }
}

/// A player can be known by a different name in each group — "Sniper" at the
/// Sunday five-a-side, their own name everywhere else. Only they can set it,
/// and only for themselves; once set, that group calls them that on the member
/// list, the board, team sheets and every scoresheet.
class AkaCard extends ConsumerStatefulWidget {
  const AkaCard({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.aka,
    required this.onSaved,
  });

  final String groupId;
  final String groupName;
  final String? aka;
  final VoidCallback onSaved;

  @override
  ConsumerState<AkaCard> createState() => _AkaCardState();
}

class _AkaCardState extends ConsumerState<AkaCard> {
  late final TextEditingController _c =
      TextEditingController(text: widget.aka ?? '');
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save(String? value) async {
    setState(() => _saving = true);
    try {
      final saved = await setGroupAka(ref, widget.groupId, value);
      ref.invalidate(myGroupAkasProvider);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
      });
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(saved == null
              ? 'Name cleared'
              : '${widget.groupName} will call you "$saved"')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final aka = widget.aka;

    if (!_editing) {
      return GlassCard(
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ALSO KNOWN AS',
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 3),
                  if (aka != null)
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: aka,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        TextSpan(
                            text: ' — what ${widget.groupName} calls you',
                            style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                        'Go by another name in ${widget.groupName}? Set one and '
                        'it shows up wherever this group lists you.',
                        style: TextStyle(
                            color: p.muted, fontSize: 12, height: 1.3)),
                ]),
          ),
          const SizedBox(width: 10),
          _MiniBtn(
            label: aka == null ? 'Set' : 'Change',
            icon: Icons.edit_outlined,
            onTap: () {
              _c.text = aka ?? '';
              setState(() => _editing = true);
            },
          ),
        ]),
      );
    }

    return GlassCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ALSO KNOWN AS',
                style: TextStyle(
                    color: p.muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            TextField(
              controller: _c,
              autofocus: true,
              maxLength: 40,
              style: TextStyle(color: p.ink, fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                hintText: 'What ${widget.groupName} calls you',
                hintStyle: TextStyle(color: p.muted, fontSize: 13),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: p.line)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
                'Only for this group — members, the board, team sheets and '
                'scoresheets here will use it. Your profile keeps your real name.',
                style: TextStyle(color: p.muted, fontSize: 11, height: 1.3)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: SpButton(
                  label: _saving ? 'Saving…' : 'Save',
                  expand: true,
                  onTap: _saving
                      ? null
                      : () =>
                          _save(_c.text.trim().isEmpty ? null : _c.text.trim()),
                ),
              ),
              const SizedBox(width: 8),
              _MiniBtn(
                label: 'Cancel',
                onTap: _saving ? null : () => setState(() => _editing = false),
              ),
            ]),
            if (aka != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: _saving ? null : () => _save(null),
                child: Text('Use my real name here',
                    style: TextStyle(
                        color: p.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: p.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: p.muted),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  color: p.ink, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
