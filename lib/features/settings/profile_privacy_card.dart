import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_models.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/data/wards/ward_models.dart'
    show wardVisibilities;
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Settings → Profile privacy, for a player who took over their account
/// under 18 (Wards 3): who can see their profile and whether search finds
/// them, while a guardian still supervises. Takes no space for everyone
/// else (the server says `applies: false`).
class ProfilePrivacySection extends ConsumerWidget {
  const ProfilePrivacySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ref.watch(myPrivacyProvider).valueOrNull;
    if (privacy == null || !privacy.applies) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Eyebrow('Profile privacy'),
        const SizedBox(height: 8),
        _PrivacyCard(privacy: privacy),
      ]),
    );
  }
}

class _PrivacyCard extends ConsumerStatefulWidget {
  const _PrivacyCard({required this.privacy});
  final MyPrivacy privacy;

  @override
  ConsumerState<_PrivacyCard> createState() => _PrivacyCardState();
}

class _PrivacyCardState extends ConsumerState<_PrivacyCard> {
  late String _visibility = _known(widget.privacy.visibility);
  late bool _searchable = widget.privacy.searchable;
  bool _busy = false;

  static String _known(String v) =>
      wardVisibilities.contains(v) ? v : 'private';

  @override
  void didUpdateWidget(covariant _PrivacyCard old) {
    super.didUpdateWidget(old);
    if (_busy || identical(old.privacy, widget.privacy)) return;
    _visibility = _known(widget.privacy.visibility);
    _searchable = widget.privacy.searchable;
  }

  Future<void> _save({String? visibility, bool? searchable}) async {
    if (_busy) return;
    final prevVisibility = _visibility;
    final prevSearchable = _searchable;
    setState(() {
      _busy = true;
      if (visibility != null) _visibility = visibility;
      if (searchable != null) _searchable = searchable;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .setMyPrivacy(visibility: visibility, searchable: searchable);
      if (mounted) ref.invalidate(myPrivacyProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _visibility = prevVisibility;
        _searchable = prevSearchable;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _hint(String v) => switch (v) {
        'groups' =>
          'Group members — people in the groups you play in can see your profile.',
        'public' => 'Everyone — anyone on SportPadi can see your profile.',
        _ =>
          'Only guardians & organisers — organisers of events you join see your name and check-in.',
      };

  /// "Ada", "Ada and Sam", "Ada, Sam and Kemi".
  static String _names(List<PrivacyGuardian> gs) {
    final n = [for (final g in gs) g.displayName];
    if (n.isEmpty) return 'your guardian';
    if (n.length == 1) return n.first;
    return '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pr = widget.privacy;
    final until = formatYmd(pr.supervisedUntil);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Who can see your profile',
            style: TextStyle(
                color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SpSegmented(
          options: const ['Private', 'Groups', 'Everyone'],
          index: wardVisibilities.indexOf(_visibility),
          onChanged: (i) {
            final v = wardVisibilities[i];
            if (v != _visibility) _save(visibility: v);
          },
        ),
        const SizedBox(height: 8),
        Text(_hint(_visibility),
            style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
        Divider(height: 26, thickness: 1, color: p.surface2),
        Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Show me in search',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text('Let people find you by name.',
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
          ),
          Switch(
            value: _searchable,
            onChanged: _busy ? null : (v) => _save(searchable: v),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.wardTint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.supervisor_account_rounded, size: 18, color: p.wardInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "You're supervised by ${_names(pr.guardians)}"
                '${until.isEmpty ? ' until you turn 18' : ' until $until'}. '
                'After that your profile follows the normal settings.',
                style: TextStyle(
                    color: p.wardInk,
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
