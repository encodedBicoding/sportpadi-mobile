import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/features/manage/create_team_screen.dart' show KitPicker;
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Pick a team logo from the gallery, upload it and save it on the team —
/// the crest's camera button (web twin: pickTeamLogo). Returns true when
/// the logo changed.
Future<bool> pickAndSaveTeamLogo(BuildContext context, WidgetRef ref, TeamDetail team) async {
  // Grab the messenger before the picker (an async gap) — no context after it.
  final messenger = ScaffoldMessenger.of(context);
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 88);
  if (picked == null) return false;
  try {
    final bytes = await picked.readAsBytes();
    final url = await ref
        .read(eventsRepositoryProvider)
        .uploadImage(bytes, picked.mimeType ?? 'image/jpeg', assetType: 'groupImage', scopeId: team.groupId);
    await ref.read(manageRepositoryProvider).updateTeam(team.id, {'logoUrl': url});
    ref.invalidate(teamDetailProvider(team.id));
    if (team.groupId != null) ref.invalidate(groupTeamsProvider(team.groupId!));
    messenger.showSnackBar(SnackBar(content: Text(l10n.team_teamLogoUpdated)));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.team_logoUploadFailed)));
  }
  return false;
}

/// Edit team — the web's EditTeamDialog as a sheet: name, @handle, grade
/// and age group, kit colours, home venue, description, logo.
Future<void> showEditTeamSheet(BuildContext context, TeamDetail team) =>
    showSpSheet<void>(context, builder: (_) => _EditTeamSheet(team: team));

class _EditTeamSheet extends ConsumerStatefulWidget {
  const _EditTeamSheet({required this.team});
  final TeamDetail team;

  @override
  ConsumerState<_EditTeamSheet> createState() => _EditTeamSheetState();
}

class _EditTeamSheetState extends ConsumerState<_EditTeamSheet> {
  late final _name = TextEditingController(text: widget.team.name);
  late final _username = TextEditingController(text: widget.team.username ?? '');
  late final _venue = TextEditingController(text: widget.team.homeVenue ?? '');
  late final _description = TextEditingController(text: widget.team.description ?? '');
  late String _grade = widget.team.grade == 'kids' ? 'kids' : 'adults';
  late int? _ageLimit = widget.team.ageLimit;
  late String _kitPrimary = widget.team.kitPrimary ?? '#16a34a';
  late String _kitSecondary = widget.team.kitSecondary ?? '#ffffff';
  late String? _logoUrl = widget.team.logoUrl;
  bool _uploading = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _venue.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 88);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref
          .read(eventsRepositoryProvider)
          .uploadImage(bytes, picked.mimeType ?? 'image/jpeg', assetType: 'groupImage', scopeId: widget.team.groupId);
      setState(() => _logoUrl = url);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.team_logoUploadFailed)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final handle = _username.text.trim().toLowerCase();
    if (name.isEmpty) return setState(() => _error = l10n.team_nameTheTeam);
    if (handle.isNotEmpty && !RegExp(r'^[a-z0-9]{2,24}$').hasMatch(handle)) {
      return setState(() => _error = l10n.team_handle224LowercaseLetters);
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(manageRepositoryProvider).updateTeam(widget.team.id, {
        'name': name,
        if (handle.isNotEmpty && handle != widget.team.username) 'username': handle,
        'grade': _grade,
        'ageLimit': _grade == 'kids' ? _ageLimit : null,
        'kitPrimary': _kitPrimary,
        'kitSecondary': _kitSecondary,
        'logoUrl': _logoUrl,
        'homeVenue': _venue.text.trim().isEmpty ? null : _venue.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      });
      ref.invalidate(teamDetailProvider(widget.team.id));
      if (widget.team.groupId != null) ref.invalidate(groupTeamsProvider(widget.team.groupId!));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.team_teamUpdated)));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(title: context.l10n.team_editTeam, icon: Icons.edit_outlined),
      // Logo + kit preview
      Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          Crest(logoUrl: _logoUrl, kitPrimary: _kitPrimary, kitSecondary: _kitSecondary, label: _name.text.trim().isEmpty ? 'T' : _name.text.trim(), size: 64),
          Positioned(
            right: -4,
            bottom: -4,
            child: Material(
              color: p.accentDeep,
              shape: CircleBorder(side: BorderSide(color: p.surface, width: 2)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _uploading ? null : _pickLogo,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: _uploading
                      ? const Padding(padding: EdgeInsets.all(7), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.photo_camera_rounded, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.l10n.team_teamLogo, style: label),
            const SizedBox(height: 2),
            Text(context.l10n.team_tapTheCameraToChange, style: TextStyle(color: p.muted, fontSize: 11.5)),
            if (_logoUrl != null)
              TextButton(
                onPressed: () => setState(() => _logoUrl = null),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, foregroundColor: p.muted),
                child: Text(context.l10n.team_removeLogo, style: const TextStyle(fontSize: 12)),
              ),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      TextField(controller: _name, maxLength: 80, decoration: InputDecoration(labelText: context.l10n.team_teamName, counterText: ''), onChanged: (_) => setState(() {})),
      const SizedBox(height: 12),
      TextField(
        controller: _username,
        maxLength: 24,
        decoration: InputDecoration(labelText: context.l10n.team_handle, prefixText: '@', counterText: '', helperText: context.l10n.team_lowercaseLettersAndNumbersHow),
      ),
      const SizedBox(height: 16),
      Text(context.l10n.team_grade, style: label),
      const SizedBox(height: 6),
      SpSegmented(
        options: const ['Adults', 'Kids'],
        index: _grade == 'kids' ? 1 : 0,
        onChanged: (i) => setState(() {
          _grade = i == 1 ? 'kids' : 'adults';
          if (_grade != 'kids') _ageLimit = null;
        }),
      ),
      if (_grade == 'kids') ...[
        const SizedBox(height: 12),
        Text(context.l10n.team_ageGroup, style: label),
        const SizedBox(height: 6),
        SpSegmented(
          options: [context.l10n.team_anyAge, for (final n in teamAgeLimits) context.l10n.team_underAge(n)],
          index: _ageLimit == null ? 0 : teamAgeLimits.indexOf(_ageLimit!) + 1,
          onChanged: (i) => setState(() => _ageLimit = i == 0 ? null : teamAgeLimits[i - 1]),
        ),
      ],
      const SizedBox(height: 16),
      Text(context.l10n.team_kitColours, style: label),
      const SizedBox(height: 8),
      KitPicker(label: context.l10n.team_primary, value: _kitPrimary, onChanged: (v) => setState(() => _kitPrimary = v)),
      const SizedBox(height: 8),
      KitPicker(label: context.l10n.team_secondary, value: _kitSecondary, onChanged: (v) => setState(() => _kitSecondary = v)),
      const SizedBox(height: 16),
      TextField(controller: _venue, maxLength: 120, decoration: InputDecoration(labelText: context.l10n.team_homeVenueOptional, counterText: '')),
      const SizedBox(height: 12),
      TextField(controller: _description, maxLines: 3, maxLength: 500, decoration: InputDecoration(labelText: context.l10n.team_descriptionOptional, counterText: '')),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
      ],
      const SizedBox(height: 16),
      SpButton(label: _busy ? context.l10n.team_saving : context.l10n.team_saveChanges, expand: true, tone: SpButtonTone.brand, onTap: _busy ? null : _save),
    ]);
  }
}
