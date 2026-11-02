import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/documents/documents_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// One document row: what's on file, upload / enter / replace / remove (web
/// twin: components/teams/TeamDocuments.tsx TeamDocumentRow). On the phone a
/// document is a photo or screenshot from the gallery / camera; PDFs are
/// uploaded on the web.
class TeamDocumentRow extends ConsumerStatefulWidget {
  const TeamDocumentRow({
    super.key,
    required this.teamId,
    required this.item,
    required this.onChanged,
    this.required = false,
  });
  final String teamId;
  final DocumentItem item;
  final bool required;
  final VoidCallback onChanged;

  @override
  ConsumerState<TeamDocumentRow> createState() => _TeamDocumentRowState();
}

class _TeamDocumentRowState extends ConsumerState<TeamDocumentRow> {
  late final _text = TextEditingController(text: widget.item.document?.textValue ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 88);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      final repo = ref.read(documentsRepositoryProvider);
      final url = await repo.upload(widget.teamId, bytes, picked.mimeType ?? 'image/jpeg');
      await repo.save(widget.teamId, widget.item.type.id,
          fileUrl: url,
          fileName: picked.name,
          textValue: _text.text.trim().isEmpty ? widget.item.document?.textValue : _text.text.trim());
      _snack('${widget.item.type.name} saved');
      widget.onChanged();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseSource() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          const ListTile(dense: true, title: Text('PDFs can be uploaded on sportpadi.com', style: TextStyle(fontSize: 12))),
        ]),
      ),
    );
    if (src != null) await _pick(src);
  }

  Future<void> _saveText() async {
    final v = _text.text.trim();
    if (v.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(documentsRepositoryProvider).save(widget.teamId, widget.item.type.id,
          fileUrl: widget.item.document?.fileUrl, fileName: widget.item.document?.fileName, textValue: v);
      _snack('${widget.item.type.name} saved');
      widget.onChanged();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${widget.item.type.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await ref.read(documentsRepositoryProvider).remove(widget.teamId, widget.item.type.id);
      widget.onChanged();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = widget.item.type;
    final d = widget.item.document;
    final ok = widget.item.ok;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: !ok && widget.required ? p.orangeTint : p.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: ok ? p.accentTint : p.surface, shape: BoxShape.circle),
            child: Icon(ok ? Icons.check_rounded : Icons.description_outlined, size: 16, color: ok ? p.greenText : p.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(t.name, style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700))),
                if (widget.required && !ok) ...[
                  const SizedBox(width: 6),
                  Text('required', style: TextStyle(color: p.orangeInk, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ]),
              if (t.description != null) Text(t.description!, style: TextStyle(color: p.muted, fontSize: 12)),
              if (d?.fileUrl != null)
                GestureDetector(
                  onTap: () => launchUrl(Uri.parse(d!.fileUrl!), mode: LaunchMode.inAppBrowserView),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.open_in_new_rounded, size: 12, color: p.greenText),
                      const SizedBox(width: 4),
                      Flexible(child: Text(d?.fileName ?? 'View file', overflow: TextOverflow.ellipsis, style: TextStyle(color: p.greenText, fontSize: 12, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ),
              if (d?.textValue != null && !t.wantsText) Text(d!.textValue!, style: TextStyle(color: p.ink, fontSize: 12)),
              if (d?.updatedAt != null)
                Text('Updated ${d!.updatedAt!.toLocal().toString().substring(0, 10)}', style: TextStyle(color: p.muted, fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 6),
          if (t.wantsFile)
            FilledButton.tonal(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: _busy ? null : _chooseSource,
              child: _busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(d?.fileUrl != null ? 'Replace' : 'Upload'),
            ),
        ]),
        if (t.wantsText) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _text,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: t.kind == 'text' ? 'Enter the details (e.g. affiliation number)' : 'Reference / number (optional with a file)',
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: _busy ? null : _saveText, child: const Text('Save')),
          ]),
        ],
        if (d != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _remove,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: p.muted),
              child: const Text('Remove', style: TextStyle(fontSize: 11.5)),
            ),
          ),
      ]),
    );
  }
}

/// The team page's Documents tab: every document its sport can ask for.
class TeamDocumentsTab extends ConsumerWidget {
  const TeamDocumentsTab({super.key, required this.teamId, required this.teamName});
  final String teamId;
  final String teamName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final docs = ref.watch(teamDocumentsProvider(teamId));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: docs.when(
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        error: (e, _) => Text(e is ApiException ? e.message : 'Could not load documents.', style: TextStyle(color: p.danger)),
        data: (items) => items.isEmpty
            ? GlassCard(
                child: Text(
                    "No documents are asked of $teamName's sport yet. When a tournament or league requires some, they'll be listed here.",
                    style: TextStyle(color: p.muted, fontSize: 13)),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Eyebrow('Team documents')),
                  SpBadge('${items.where((i) => i.ok).length}/${items.length}'),
                ]),
                const SizedBox(height: 4),
                Text('Keep these on file once; tournaments and leagues that require them take a copy when you register.',
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
                const SizedBox(height: 10),
                for (final i in items)
                  TeamDocumentRow(teamId: teamId, item: i, onChanged: () => ref.invalidate(teamDocumentsProvider(teamId))),
                Text(
                    "Organisers see exactly what's on file when they review your registration; keep documents current yourself — SportPadi doesn't track expiry.",
                    style: TextStyle(color: p.muted, fontSize: 11)),
              ]),
      ),
    );
  }
}

/// Pick which documents registering teams must have (organiser), from the
/// owner-console catalogue for a sport.
class DocumentPicker extends ConsumerWidget {
  const DocumentPicker({super.key, required this.categoryId, required this.value, required this.onChanged});
  final String? categoryId;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final types = ref.watch(documentTypesProvider(categoryId ?? '')).valueOrNull ?? const <DocumentType>[];
    if (types.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Required documents (optional)', style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      for (final t in types)
        GestureDetector(
          onTap: () => onChanged(value.contains(t.id) ? value.where((x) => x != t.id).toList() : [...value, t.id]),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: value.contains(t.id) ? p.accentTint : p.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: value.contains(t.id) ? p.accent : Colors.transparent, width: 2),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(value.contains(t.id) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  size: 20, color: value.contains(t.id) ? p.greenText : p.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t.name}${t.youthOnly ? '  · kids teams only' : ''}',
                      style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w700)),
                  if (t.description != null) Text(t.description!, style: TextStyle(color: p.muted, fontSize: 11.5)),
                ]),
              ),
            ]),
          ),
        ),
      Text("Teams upload these once on their team page. You see a snapshot with each registration and decide; SportPadi doesn't check expiry.",
          style: TextStyle(color: p.muted, fontSize: 11)),
    ]);
  }
}
