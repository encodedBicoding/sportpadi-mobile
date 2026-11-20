import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/join/join_models.dart';
import 'package:sportpadi_mobile/data/join/join_repository.dart';
import 'package:sportpadi_mobile/features/share/share_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// Scopes whose sheet is open: a second tap doesn't open a second one.
final Set<String> _open = {};

/// The share sheet for a SECRET invite link (docs/wiki/sharing.md "Invite
/// links" in the workspace; reviews/invite-links.md): a group's membership
/// link or a team's join link. Only the group's admins have it — the server
/// refuses anyone else. The sheet opens at once and loads the link (a
/// spinner meanwhile, the server's reason on failure), then is the ordinary
/// share sheet with "Reset link" under the other apps: a new code, the old
/// link stops working at once (a GROUP reset also resets its team links),
/// and the sheet swaps to the new link in place.
Future<void> showInviteLinkSheet(
  BuildContext context,
  WidgetRef ref, {
  required InviteScope scope,
  String? title,
  String? text,
  String? subtitle,
  String? notice,
  String? imageUrl,
  String Function(String url)? decorate,
}) async {
  final key = scope.apiPath;
  if (!_open.add(key)) return;
  try {
    await showSpSheet<void>(
      context,
      builder: (_) => _InviteLinkSheet(
        scope: scope,
        title: title,
        text: text,
        subtitle: subtitle,
        notice: notice,
        imageUrl: imageUrl,
        decorate: decorate,
      ),
    );
  } finally {
    _open.remove(key);
  }
}

class _InviteLinkSheet extends ConsumerStatefulWidget {
  const _InviteLinkSheet({
    required this.scope,
    this.title,
    this.text,
    this.subtitle,
    this.notice,
    this.imageUrl,
    this.decorate,
  });

  final InviteScope scope;
  final String? title;
  final String? text;
  final String? subtitle;
  final String? notice;
  final String? imageUrl;
  final String Function(String url)? decorate;

  @override
  ConsumerState<_InviteLinkSheet> createState() => _InviteLinkSheetState();
}

class _InviteLinkSheetState extends ConsumerState<_InviteLinkSheet> {
  InviteLink? _link;
  String? _error;
  bool _justReset = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Always asked fresh: another admin may have reset it since.
  Future<void> _load() async {
    final repo = ref.read(joinRepositoryProvider);
    try {
      final l = await repo.inviteLink(widget.scope);
      if (mounted) setState(() => _link = l);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _retry() {
    setState(() => _error = null);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final link = _link;
    if (link == null) {
      if (_error == null) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13)),
          const SizedBox(height: 8),
          TextButton(onPressed: _retry, child: Text(context.l10n.share_tryAgain)),
        ]),
      );
    }
    final raw = shareSiteUrl(ref.read(appConfigProvider).apiBaseUrl, link.path);
    final url = widget.decorate == null ? raw : widget.decorate!(raw);
    return shareSheetBody(
      // A new link is a new sheet body (its picks and preview were for the old one).
      key: ValueKey(url),
      url: url,
      title: widget.title,
      text: widget.text,
      subtitle: widget.subtitle,
      notice: widget.notice,
      imageUrl: widget.imageUrl,
      extra: (_) => _ResetInviteLink(
        scope: widget.scope,
        justReset: _justReset,
        onReset: (l) => setState(() {
          _link = l;
          _justReset = true;
        }),
      ),
    );
  }
}

/// "Reset link", with an inline confirm (a dialog over the sheet would be one
/// layer too many): the old link will stop working — and, for a group, every
/// team link in it too.
class _ResetInviteLink extends ConsumerStatefulWidget {
  const _ResetInviteLink({
    required this.scope,
    required this.justReset,
    required this.onReset,
  });
  final InviteScope scope;
  final bool justReset;
  final ValueChanged<InviteLink> onReset;

  @override
  ConsumerState<_ResetInviteLink> createState() => _ResetInviteLinkState();
}

class _ResetInviteLinkState extends ConsumerState<_ResetInviteLink> {
  bool _confirming = false;
  bool _busy = false;
  String? _error;

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(joinRepositoryProvider);
    try {
      final l = await repo.resetInviteLink(widget.scope);
      // The sheet swaps to the new link (this widget is rebuilt fresh).
      widget.onReset(l);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    if (!_confirming) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.justReset) ...[
          Text(l.share_linkWasReset,
              style: TextStyle(color: p.greenText, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
        ],
        Row(children: [
          Expanded(
            child: Text(l.share_resetLinkHint,
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() => _confirming = true),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l.share_resetLink),
          ),
        ]),
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            widget.scope.teamId != null
                ? l.share_resetLinkConfirm
                : l.share_resetGroupLinkConfirm,
            style: TextStyle(color: p.ink, fontSize: 13)),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
        ],
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _confirming = false;
                      _error = null;
                    }),
            child: Text(l.common_cancel),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _reset,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l.share_resetLink),
          ),
        ]),
      ]),
    );
  }
}
