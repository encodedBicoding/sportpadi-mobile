import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/discussions/discussion_models.dart';
import 'package:sportpadi_mobile/data/discussions/discussions_repository.dart';
import 'package:sportpadi_mobile/data/messages/message_models.dart'
    show MessageAttachment;
import 'package:sportpadi_mobile/features/discussions/discussion_widgets.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/inbox/message_widgets.dart'
    show PendingImagesStrip, pickMessageImage;
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Start a discussion: where (group-wide or a team — as a ward's guardian
/// when I'm on it only through them), flair, title, body and up to 4 photos.
/// `/groups/:id/discussions/new?team=<teamId|group>` preselects the space.
class DiscussionComposerScreen extends ConsumerStatefulWidget {
  const DiscussionComposerScreen(
      {super.key, required this.groupId, this.initialSpace});
  final String groupId;
  final String? initialSpace;

  @override
  ConsumerState<DiscussionComposerScreen> createState() =>
      _DiscussionComposerScreenState();
}

class _DiscussionComposerScreenState
    extends ConsumerState<DiscussionComposerScreen> {
  static const _maxImages = 4;

  final _title = TextEditingController();
  final _body = TextEditingController();
  final List<MessageAttachment> _images = [];

  /// `group` or a team id; null until the spaces load.
  String? _space;
  String? _wardId;
  String _flair = 'general';
  bool _uploading = false;
  bool _posting = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Pick the space once: the one asked for when I can post there, else
  /// group-wide, else my first team.
  void _seed(DiscussionSpaces s) {
    if (_space != null) return;
    final want = widget.initialSpace;
    if (want == 'group' && s.group) {
      _space = 'group';
    } else if (want != null && s.team(want) != null) {
      _space = want;
    } else if (s.group) {
      _space = 'group';
    } else if (s.teams.isNotEmpty) {
      _space = s.teams.first.id;
    }
  }

  List<DiscussionWardRef> _wards(DiscussionSpaces s) =>
      s.team(_space)?.asGuardianOf ?? const [];

  /// The ward I post for (when I'm on the team only through my wards).
  String? _ward(DiscussionSpaces s) {
    final wards = _wards(s);
    if (wards.isEmpty) return null;
    return wards.any((w) => w.id == _wardId) ? _wardId : wards.first.id;
  }

  bool get _canPost =>
      _space != null &&
      !_posting &&
      !_uploading &&
      _title.text.trim().length >= 3;

  Future<void> _addImage() async {
    if (_images.length >= _maxImages || _uploading) return;
    setState(() => _uploading = true);
    try {
      final a = await pickMessageImage(ref, widget.groupId);
      if (a != null && mounted) setState(() => _images.add(a));
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _post(DiscussionSpaces s) async {
    final space = _space;
    if (!_canPost || space == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _posting = true);
    try {
      final id = await ref.read(discussionsRepositoryProvider).create(
            groupId: widget.groupId,
            teamId: space == 'group' ? null : space,
            title: _title.text.trim(),
            body: _body.text.trim(),
            flair: _flair,
            attachments: List.of(_images),
            viaWardId: _ward(s),
          );
      if (!mounted) return;
      ref.invalidate(discussionListProvider);
      context.pushReplacement('/discussions/$id');
    } catch (e) {
      _snack('$e');
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final spaces = ref.watch(discussionSpacesProvider(widget.groupId));
    final s = spaces.valueOrNull;
    if (s != null) _seed(s);
    final groupName = ref.watch(groupProvider(widget.groupId)).valueOrNull?.name;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(title: 'New discussion', subtitle: groupName),
          ),
          Expanded(
            child: AsyncView<DiscussionSpaces>(
              value: spaces,
              onRetry: () =>
                  ref.invalidate(discussionSpacesProvider(widget.groupId)),
              data: (info) {
                if (!info.any) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                          "You can't start discussions in this group.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.muted)),
                    ),
                  );
                }
                return _form(p, info, groupName);
              },
            ),
          ),
          if (s != null && s.any)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              decoration: BoxDecoration(
                color: p.bg,
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: SpButton(
                label: _posting ? 'Posting…' : 'Post',
                icon: Icons.send_rounded,
                tone: SpButtonTone.brand,
                expand: true,
                onTap: _canPost ? () => _post(s) : null,
              ),
            ),
        ]),
      ),
    );
  }

  Widget _form(AppPalette p, DiscussionSpaces s, String? groupName) {
    final team = s.team(_space);
    final wards = _wards(s);
    final wardId = _ward(s);
    String? wardName;
    for (final w in wards) {
      if (w.id == wardId) wardName = w.firstName;
    }
    final visibility = team == null
        ? 'Everyone in ${groupName ?? 'the group'} can see it.'
        : "${team.name}'s players, their guardians, its coaches and the "
            "group's admins can see it.";
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const Eyebrow('Where'),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (s.group)
            DiscussionPill(
              label: 'Whole group',
              icon: Icons.groups_outlined,
              selected: _space == 'group',
              onTap: () => setState(() => _space = 'group'),
            ),
          for (final t in s.teams)
            DiscussionPill(
              label: t.name,
              leading: Crest(logoUrl: t.logoUrl, label: t.name, size: 18),
              selected: _space == t.id,
              onTap: () => setState(() => _space = t.id),
            ),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.visibility_outlined, size: 15, color: p.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(visibility,
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
          ),
        ]),
        if (wardName != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: p.wardTint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.child_care_rounded, size: 16, color: p.wardInk),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text("Posting as $wardName's guardian",
                        style: TextStyle(
                            color: p.wardInk,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
                if (wards.length > 1) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final w in wards)
                      DiscussionPill(
                        label: w.firstName,
                        selected: w.id == wardId,
                        onTap: () => setState(() => _wardId = w.id),
                      ),
                  ]),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        const Eyebrow('Flair'),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in discussionFlairs)
            DiscussionPill(
              label: f.label,
              icon: discussionFlairIcon(f.value),
              selected: _flair == f.value,
              onTap: () => setState(() => _flair = f.value),
            ),
        ]),
        const SizedBox(height: 22),
        const Eyebrow('Discussion'),
        const SizedBox(height: 10),
        GlassCard(
          child: Column(children: [
            TextField(
              controller: _title,
              maxLength: 140,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                helperText: 'At least 3 characters.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _body,
              maxLength: 5000,
              minLines: 5,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                alignLabelWithHint: true,
                helperText: 'Plain text. Links will be tappable.',
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (_images.isNotEmpty) ...[
          PendingImagesStrip(
            images: _images,
            onRemove: (a) => setState(() => _images.remove(a)),
          ),
          const SizedBox(height: 10),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _images.length >= _maxImages || _uploading || _posting
                ? null
                : _addImage,
            icon: _uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_photo_alternate_outlined, size: 19),
            label: Text(_images.isEmpty
                ? 'Add photos'
                : 'Add photo (${_images.length}/$_maxImages)'),
          ),
        ),
      ],
    );
  }
}
