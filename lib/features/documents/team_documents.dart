import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/documents/documents_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

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
      _snack(l10n.manage_saved(widget.item.type.name));
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
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(l10n.manage_chooseFromGallery), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(l10n.manage_takeAPhoto), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(dense: true, title: Text(l10n.manage_pDFsCanBeUploadedOn, style: const TextStyle(fontSize: 12))),
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
      _snack(l10n.manage_saved(widget.item.type.name));
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
        title: Text(l10n.manage_remove2(widget.item.type.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.manage_keep)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.manage_remove3)),
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
                  Text(context.l10n.manage_requiredLabel, style: TextStyle(color: p.orangeInk, fontSize: 11, fontWeight: FontWeight.w600)),
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
                      Flexible(child: Text(d?.fileName ?? context.l10n.manage_viewFile, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.greenText, fontSize: 12, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ),
              if (d?.textValue != null && !t.wantsText) Text(d!.textValue!, style: TextStyle(color: p.ink, fontSize: 12)),
              if (d?.updatedAt != null)
                Text(context.l10n.manage_updated2(d!.updatedAt!.toLocal().toString().substring(0, 10)), style: TextStyle(color: p.muted, fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 6),
          if (t.wantsFile)
            FilledButton.tonal(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: _busy ? null : _chooseSource,
              child: _busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(d?.fileUrl != null ? context.l10n.manage_replace : context.l10n.manage_upload),
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
                  hintText: t.kind == 'text' ? context.l10n.manage_enterTheDetailsEG : context.l10n.manage_referenceNumberOptionalWithA,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: _busy ? null : _saveText, child: Text(context.l10n.manage_save)),
          ]),
        ],
        if (d != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _remove,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: p.muted),
              child: Text(context.l10n.manage_remove3, style: const TextStyle(fontSize: 11.5)),
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
        error: (e, _) => Text(e is ApiException ? e.message : context.l10n.manage_couldNotLoadDocuments, style: TextStyle(color: p.danger)),
        data: (items) => items.isEmpty
            ? GlassCard(
                child: Text(
                    context.l10n.manage_noDocumentsAreAskedOf(teamName),
                    style: TextStyle(color: p.muted, fontSize: 13)),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Eyebrow(context.l10n.manage_teamDocuments)),
                  SpBadge('${items.where((i) => i.ok).length}/${items.length}'),
                ]),
                const SizedBox(height: 4),
                Text(context.l10n.manage_keepTheseOnFileOnce,
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
                const SizedBox(height: 10),
                for (final i in items)
                  TeamDocumentRow(teamId: teamId, item: i, onChanged: () => ref.invalidate(teamDocumentsProvider(teamId))),
                Text(
                    context.l10n.manage_organisersSeeExactlyWhatsOn,
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
      Text(context.l10n.manage_requiredDocumentsOptional, style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
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
      Text(context.l10n.manage_teamsUploadTheseOnceOn,
          style: TextStyle(color: p.muted, fontSize: 11)),
    ]);
  }
}
