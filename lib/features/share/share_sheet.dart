import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/share/share_models.dart';
import 'package:sportpadi_mobile/data/share/share_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/share/share_intents.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// The share sheet (docs/wiki/sharing.md in the workspace) — one for every
/// shareable thing, Instagram / TikTok style, the web's `ShareSheet` on a
/// phone:
///   • the item's card on top (`share` preview, as THIS viewer may see it);
///   • "Send to": my open threads, then people I could start a profile DM
///     with — search, multi-select (10 at most), an optional message, Send;
///     each recipient answers for itself (Messages' own rules);
///   • other apps: Copy link, WhatsApp, X, Facebook, Telegram, Messages,
///     Email, More (the phone's own share sheet).
/// Signed out: the card and the other apps only — nothing that needs an
/// account is asked for.
///
/// [url] is copied / sent to other apps as given (it may carry `?ref=`);
/// in-app sends carry the item's canonical link (the server's). [text] is a
/// page's own wording (a call for teams, a ticket) and may hold the link.
/// [notice] stays in sight under the card whatever the server's card says
/// (the membership link's "anyone with it can join" — fix round, review L3).
/// [extra] goes under the other apps (a league's table image and widget).
Future<void> showShareSheet(
  BuildContext context,
  WidgetRef ref, {
  required String url,
  String? title,
  String? text,
  String? subtitle,
  String? imageUrl,
  String? notice,
  WidgetBuilder? extra,
}) =>
    showSpSheet<void>(
      context,
      builder: (_) => _ShareSheet(
        url: url,
        title: (title == null || title.trim().isEmpty) ? url : title,
        text: text,
        subtitle: subtitle,
        imageUrl: imageUrl,
        notice: notice,
        extra: extra,
      ),
    );

/// The site's address for a path (`/players/<id>`): share links are web links.
String shareSiteUrl(String base, String path) =>
    '${base.replaceAll(RegExp(r'/+$'), '')}$path';

/// Same caps as the server (routers/share.ts).
const _maxRecipients = 10;
const _noteMax = 1000;

IconData shareKindIcon(String? kind) => switch (kind) {
      'event' => Icons.event_rounded,
      'group' => Icons.groups_rounded,
      'group_invite' => Icons.person_add_alt_1_rounded,
      'tournament' => Icons.emoji_events_rounded,
      'league' => Icons.military_tech_rounded,
      'competition' => Icons.emoji_events_outlined,
      'highlight' => Icons.movie_filter_outlined,
      'ticket' => Icons.confirmation_number_outlined,
      'team_invite' => Icons.person_add_alt_1_rounded,
      'call_for_teams' => Icons.campaign_rounded,
      'player' => Icons.person_rounded,
      'match' => Icons.sports_soccer_rounded,
      'team' => Icons.shield_outlined,
      _ => Icons.ios_share_rounded,
    };

String? shareKindLabel(BuildContext context, String? kind) {
  final l = context.l10n;
  return switch (kind) {
    'event' => l.share_kindEvent,
    'group' => l.share_kindGroup,
    'group_invite' => l.share_kindGroupInvite,
    'tournament' => l.share_kindTournament,
    'league' => l.share_kindLeague,
    'competition' => l.share_kindCompetition,
    'highlight' => l.share_kindHighlight,
    'ticket' => l.share_kindTicket,
    'team_invite' => l.share_kindTeamInvite,
    'call_for_teams' => l.share_kindCallForTeams,
    'player' => l.share_kindPlayer,
    'match' => l.share_kindMatch,
    'team' => l.share_kindTeam,
    _ => null,
  };
}

/// The item's card: picture (or the kind's icon), kind, title, one line.
/// Also the card under a link in a chat (`share_link_cards.dart`).
class SharePreviewCard extends StatelessWidget {
  const SharePreviewCard({
    super.key,
    required this.kind,
    required this.title,
    this.subtitle,
    this.imageUrl,
  });

  final String? kind;
  final String title;
  final String? subtitle;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kindLabel = shareKindLabel(context, kind);
    final icon = Icon(shareKindIcon(kind), size: 24, color: p.greenText);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.line),
      ),
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.accentTint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: imageUrl == null
              ? icon
              : CachedNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => icon,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kindLabel != null)
                Text(kindLabel.toUpperCase(),
                    style: TextStyle(
                        color: p.greenText,
                        fontSize: 10.5,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800)),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      height: 1.25,
                      fontWeight: FontWeight.w800)),
              if (subtitle != null)
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Stops at [max] UTF-16 units — what the server's length checks count
/// (`TextField.maxLength` counts what a person sees as one character). A
/// paste that runs over is cut at the limit (never half an emoji), not
/// dropped.
class _Utf16Limit extends TextInputFormatter {
  const _Utf16Limit(this.max);
  final int max;
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.length <= max) return newValue;
    var end = max;
    // Don't split a surrogate pair.
    final unit = text.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end--;
    final cut = text.substring(0, end);
    return TextEditingValue(
      text: cut,
      selection: TextSelection.collapsed(offset: cut.length),
    );
  }
}

/// The sheet's body, for a caller that runs its own sheet around it (the
/// invite-link sheet loads its link first and swaps it after a reset — give
/// it a key that changes with [url]).
Widget shareSheetBody({
  Key? key,
  required String url,
  String? title,
  String? text,
  String? subtitle,
  String? imageUrl,
  String? notice,
  WidgetBuilder? extra,
}) =>
    _ShareSheet(
      key: key,
      url: url,
      title: (title == null || title.trim().isEmpty) ? url : title,
      text: text,
      subtitle: subtitle,
      imageUrl: imageUrl,
      notice: notice,
      extra: extra,
    );

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({
    super.key,
    required this.url,
    required this.title,
    this.text,
    this.subtitle,
    this.imageUrl,
    this.notice,
    this.extra,
  });

  final String url;
  final String title;
  final String? text;
  final String? subtitle;
  final String? imageUrl;
  final String? notice;
  final WidgetBuilder? extra;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _search = TextEditingController();
  final _note = TextEditingController();
  Timer? _debounce;
  String _q = '';
  List<ShareRecipient> _people = const [];
  bool _loadingPeople = false;
  bool _peopleLoaded = false;
  String? _peopleError;
  int _gen = 0;
  List<ShareRecipient> _picked = [];
  Map<String, ShareSendResult> _results = {};
  bool _sending = false;
  String? _sendError;

  /// Asked for the people row once someone is signed in — at open, or when
  /// the session turns up later (fix round, app review LOW-1).
  bool _peopleAsked = false;

  // Said INSIDE the sheet: a snackbar from here is painted on the page's
  // Scaffold, under the sheet and its barrier (app review MED-1).
  bool _copied = false;
  Timer? _copiedTimer;
  bool _atCap = false;
  String? _partial;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _debounce?.cancel();
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    final gen = ++_gen;
    setState(() {
      _loadingPeople = true;
      _peopleError = null;
    });
    try {
      final list = await ref
          .read(shareRepositoryProvider)
          .recipients(q: _q.isEmpty ? null : _q, limit: 20);
      if (!mounted || gen != _gen) return;
      setState(() {
        _people = list;
        _loadingPeople = false;
        _peopleLoaded = true;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loadingPeople = false;
        _peopleLoaded = true;
        _peopleError = '$e';
      });
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _q = v.trim();
      unawaited(_loadPeople());
    });
  }

  void _toggle(ShareRecipient r) {
    final on = _picked.any((x) => x.key == r.key);
    if (on) {
      setState(() {
        _picked = _picked.where((x) => x.key != r.key).toList();
        _atCap = false;
      });
      return;
    }
    if (_picked.length >= _maxRecipients) {
      setState(() => _atCap = true);
      return;
    }
    setState(() {
      _picked = [..._picked, r];
      _atCap = false;
    });
  }

  Future<void> _send() async {
    if (_picked.isEmpty || _sending) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final picked = List<ShareRecipient>.of(_picked);
    setState(() {
      _sending = true;
      _sendError = null;
      _partial = null;
    });
    try {
      final out = await ref
          .read(shareRepositoryProvider)
          .send(url: widget.url, to: picked, note: _note.text);
      if (!mounted) return;
      final res = Map<String, ShareSendResult>.of(_results);
      for (var i = 0; i < picked.length; i++) {
        res[picked[i].key] = i < out.results.length
            ? out.results[i]
            : const ShareSendResult(ok: false);
      }
      final failed = picked.where((r) => res[r.key]?.ok != true).toList();
      if (failed.isEmpty) {
        nav.pop();
        messenger
            .showSnackBar(SnackBar(content: Text(l.share_sentToAll(out.sent))));
        return;
      }
      // Keep only the ones that didn't go, with why, to retry or drop —
      // said in the sheet, which stays open.
      setState(() {
        _results = res;
        _picked = failed;
        _sending = false;
        _partial = out.sent > 0
            ? l.share_sentSome(out.sent, picked.length)
            : l.share_couldntSend;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = '$e';
      });
    }
  }

  /// The Copy tile itself says "Link copied" for two seconds.
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// Where an iPad's share popover points: the tapped button.
  Rect? _originOf(BuildContext c) {
    final box = c.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _native(Rect? origin) async {
    final m = shareMessage(url: widget.url, title: widget.title, text: widget.text);
    try {
      await SharePlus.instance.share(ShareParams(
        text: m.message,
        subject: widget.title,
        sharePositionOrigin: origin,
      ));
    } catch (_) {
      // Nothing to share with: Copy link is still there.
    }
  }

  /// https intents open the app when it's installed, the site when not;
  /// sms: / mailto: open the phone's own. No `canLaunchUrl` (it would need
  /// query schemes / <queries>): just try, and fall back to the phone's own
  /// share sheet when nothing took it.
  Future<void> _launch(ShareApp app, Rect? origin) async {
    final uri = Uri.parse(shareIntentUrl(app,
        url: widget.url, title: widget.title, text: widget.text));
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) await _native(origin);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final me = ref.watch(authControllerProvider).valueOrNull?.user?.id;
    // The people row, asked once someone is signed in — also when the session
    // only turned up after the sheet opened (app review LOW-1). Signed out:
    // never asked.
    if (me != null && !_peopleAsked) {
      _peopleAsked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadPeople());
      });
    }
    final pk = (viewer: me, url: widget.url);
    final pv = ref.watch(sharePreviewProvider(pk));
    final got = pv.valueOrNull;
    final card = got != null && got.available ? got : null;
    // Only the server's own "unavailable" says the link can't be sent; a
    // request that FAILED says nothing about it (review L1) — the row stays
    // and the server decides on Send.
    final unavailable = got != null && !got.available;
    final canSend = me != null && !unavailable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SpSheetHeader(title: l.share_share, icon: Icons.ios_share_rounded),
        SharePreviewCard(
          kind: card?.kind,
          title: card?.title ?? widget.title,
          subtitle: card != null ? card.subtitle : widget.subtitle,
          imageUrl: card != null ? card.imageUrl : widget.imageUrl,
        ),
        if (widget.notice != null) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, end: 6, top: 1),
              child: Icon(Icons.info_outline_rounded, size: 15, color: p.muted),
            ),
            Expanded(
              child: Text(widget.notice!,
                  style: TextStyle(color: p.muted, fontSize: 12.5)),
            ),
          ]),
        ],
        if (pv.hasError && !pv.isLoading) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
            decoration: BoxDecoration(
                color: p.surface2, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Expanded(
                child: Text(l.share_couldntLoadPreview,
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
              ),
              TextButton(
                onPressed: () => ref.invalidate(sharePreviewProvider(pk)),
                child: Text(l.share_tryAgain),
              ),
            ]),
          ),
        ],
        if (canSend) ...[
          const SizedBox(height: 18),
          _sendTo(context),
        ],
        if (me != null && unavailable) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: p.surface2, borderRadius: BorderRadius.circular(16)),
            child: Text(l.share_cantSendInApp,
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ),
        ],
        const SizedBox(height: 18),
        _sectionTitle(context, l.share_otherApps),
        const SizedBox(height: 8),
        _otherApps(context),
        if (widget.extra != null) ...[
          const SizedBox(height: 14),
          Divider(color: p.line, height: 1),
          const SizedBox(height: 14),
          Builder(builder: widget.extra!),
        ],
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text, {Widget? trailing}) {
    final p = context.palette;
    return Row(children: [
      Expanded(
        child: Text(text,
            style: TextStyle(
                color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
      ),
      if (trailing != null) trailing,
    ]);
  }

  Widget _sendTo(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final shown = {for (final r in _people) r.key};
    // Someone picked before the search changed stays in the row, first.
    final items = [
      ..._picked.where((r) => !shown.contains(r.key)),
      ..._people,
    ];
    final failures = [
      for (final r in _picked)
        if (_results[r.key]?.ok == false) r,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionTitle(context, l.share_sendTo,
            trailing: _loadingPeople
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: p.muted))
                : null),
        const SizedBox(height: 8),
        TextField(
          controller: _search,
          onChanged: _onSearch,
          textInputAction: TextInputAction.search,
          inputFormatters: const [_Utf16Limit(60)],
          decoration: InputDecoration(
            hintText: l.share_searchPeople,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              _peopleError ??
                  (!_peopleLoaded || _loadingPeople
                      ? l.share_loadingPeople
                      : _q.isNotEmpty
                          ? l.share_noMatches
                          : l.share_noOneYet),
              style: TextStyle(color: p.muted, fontSize: 12.5),
            ),
          )
        else
          SizedBox(
            // Grows with the text size: two lines of name and a sub-line.
            height: 74 + MediaQuery.textScalerOf(context).scale(52),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, i) => _person(context, items[i]),
            ),
          ),
        if (_atCap) ...[
          const SizedBox(height: 6),
          Text(l.share_maxRecipients(_maxRecipients),
              style: TextStyle(color: p.muted, fontSize: 12.5)),
        ],
        if (_partial != null) ...[
          const SizedBox(height: 6),
          Text(_partial!,
              style: TextStyle(
                  color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
        if (failures.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: p.liveTint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in failures)
                  Text(
                      l.share_couldntSendTo(
                          r.name, _results[r.key]?.error ?? l.share_couldntSend),
                      style: TextStyle(color: p.danger, fontSize: 12.5)),
              ],
            ),
          ),
        ],
        if (_picked.isNotEmpty) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: const [_Utf16Limit(_noteMax)],
            decoration: InputDecoration(hintText: l.share_addMessage, isDense: true),
          ),
          if (_sendError != null) ...[
            const SizedBox(height: 6),
            Text(_sendError!, style: TextStyle(color: p.danger, fontSize: 12.5)),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(_sending
                ? l.share_sending
                : l.share_sendToCount(_picked.length)),
          ),
        ],
      ],
    );
  }

  Widget _person(BuildContext context, ShareRecipient r) {
    final p = context.palette;
    final l = context.l10n;
    final on = _picked.any((x) => x.key == r.key);
    final res = _results[r.key];
    final sub = r.aboutWard != null ? l.share_aboutWard(r.aboutWard!) : r.context;
    return Semantics(
      button: true,
      selected: on,
      label: on ? '${r.name}, ${l.share_selected}' : r.name,
      excludeSemantics: true,
      child: Tooltip(
        message: res?.ok == false ? (res?.error ?? l.share_couldntSend) : r.name,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // A pick made while sending would be overwritten by the result.
          onTap: _sending ? null : () => _toggle(r),
          child: SizedBox(
            width: 76,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(clipBehavior: Clip.none, children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: on ? p.accent : Colors.transparent, width: 2),
                    ),
                    child: WardAvatar(name: r.name, url: r.avatarUrl, size: 52),
                  ),
                  if (on)
                    PositionedDirectional(
                      end: -2,
                      bottom: -2,
                      child: _dot(context, p.accent,
                          const Icon(Icons.check_rounded, size: 13, color: Colors.white)),
                    ),
                  if (res?.ok == false)
                    PositionedDirectional(
                      end: -2,
                      top: -2,
                      child: _dot(
                          context,
                          p.danger,
                          const Text('!',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900))),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(r.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 11.5,
                        height: 1.15,
                        fontWeight: FontWeight.w600)),
                if (sub != null)
                  Text(sub,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 10.5)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dot(BuildContext context, Color color, Widget child) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: context.palette.bg, width: 2),
        ),
        child: child,
      );

  Widget _otherApps(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    Widget app(String label, Widget icon, Color tint,
            void Function(Rect? origin) onTap) =>
        Builder(
          builder: (c) => Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onTap(_originOf(c)),
              child: SizedBox(
                width: 72,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: p.surface2, shape: BoxShape.circle),
                      child: IconTheme(
                          data: IconThemeData(color: tint, size: 25),
                          child: icon),
                    ),
                    const SizedBox(height: 6),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
        );
    final apps = <Widget>[
      app(_copied ? l.share_linkCopied : l.share_copyLink,
          Icon(_copied ? Icons.check_rounded : Icons.link_rounded), p.ink,
          (_) => unawaited(_copy())),
      app('WhatsApp', const Icon(Icons.chat_bubble_outline_rounded), const Color(0xFF25D366),
          (o) => unawaited(_launch(ShareApp.whatsapp, o))),
      app(
          'X',
          Text('X',
              style: TextStyle(
                  color: p.ink, fontSize: 21, fontWeight: FontWeight.w900)),
          p.ink,
          (o) => unawaited(_launch(ShareApp.x, o))),
      app(
          'Facebook',
          const Text('f',
              style: TextStyle(
                  color: Color(0xFF1877F2),
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
          const Color(0xFF1877F2),
          (o) => unawaited(_launch(ShareApp.facebook, o))),
      app('Telegram', const Icon(Icons.send_rounded), const Color(0xFF26A5E4),
          (o) => unawaited(_launch(ShareApp.telegram, o))),
      app(l.share_sms, const Icon(Icons.forum_outlined), p.ink,
          (o) => unawaited(_launch(ShareApp.sms, o))),
      app(l.share_email, const Icon(Icons.mail_outline_rounded), p.ink,
          (o) => unawaited(_launch(ShareApp.email, o))),
      app(l.share_more, const Icon(Icons.more_horiz_rounded), p.ink,
          (o) => unawaited(_native(o))),
    ];
    return SizedBox(
      height: 72 + MediaQuery.textScalerOf(context).scale(20),
      child: ListView(scrollDirection: Axis.horizontal, children: apps),
    );
  }
}
