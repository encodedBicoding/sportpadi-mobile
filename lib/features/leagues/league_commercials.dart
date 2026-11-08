import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/leagues/league_sheets.dart';
import 'package:sportpadi_mobile/features/leagues/league_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Organiser console → sponsors & match tickets, in the app (web
/// LeagueCommercials): one title sponsor ("presented by") and partners with
/// logo upload — each sponsor takes a sponsor spot bought from SportPadi
/// (card checkout in the group wallet's currency, owner-set price); the
/// match-ticket preset each published fixture's spectator ticket is made from.

String spotMoney(int minor, String currency, int exp) {
  var div = 1;
  for (var i = 0; i < exp; i++) {
    div *= 10;
  }
  final v = minor / div;
  final s = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(exp);
  return '$currency $s';
}

typedef _Sponsor = ({String name, String? url, String? logoUrl, String tier});

_Sponsor _sponsorOf(J s) => (name: s.str('name'), url: s.s('url'), logoUrl: s.s('logoUrl'), tier: s.s('tier') == 'title' ? 'title' : 'partner');
Map<String, dynamic> _sponsorJson(_Sponsor s) => {'name': s.name, 'url': s.url, 'logoUrl': s.logoUrl, 'tier': s.tier};

Future<void> showSponsorsSheet(BuildContext context, WidgetRef ref, {required J data, required String groupId}) =>
    showSpSheet<void>(context, builder: (_) => _SponsorsSheet(data: data, groupId: groupId));

class _SponsorsSheet extends ConsumerStatefulWidget {
  const _SponsorsSheet({required this.data, required this.groupId});
  final J data;
  final String groupId;
  @override
  ConsumerState<_SponsorsSheet> createState() => _SponsorsSheetState();
}

class _SponsorsSheetState extends ConsumerState<_SponsorsSheet> {
  late List<_Sponsor> _list = [for (final s in widget.data.list('sponsors')) _sponsorOf(s)];
  late int _owned = widget.data.o('spots')?.i('owned') ?? 0;
  // Sponsorship Terms: the sheet stays locked until the group accepts them.
  late bool _termsOk = widget.data.o('sponsorTerms')?.b('accepted') == true;
  bool _busy = false;
  bool _checking = false;

  J? get _spots => widget.data.o('spots');

  // SportPadi takedowns: the whole league suspended, or single sponsors (matched by name).
  String? get _suspended => widget.data.o('takedowns')?.o('suspended')?.s('reason');
  String? _downReason(_Sponsor s) {
    final key = s.name.trim().toLowerCase();
    for (final d in widget.data.o('takedowns')?.list('sponsors') ?? const <J>[]) {
      if (d.s('nameKey') == key) return d.s('reason');
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Back from a spot checkout? Settle any payment that went through.
    if (_termsOk) WidgetsBinding.instance.addPostFrameCallback((_) => _confirm(quiet: true));
  }

  Future<void> _confirm({bool quiet = false}) async {
    if (!mounted) return;
    setState(() => _checking = true);
    try {
      final r = J.of(await ref.read(leaguesRepositoryProvider).mutate('confirmSponsorSpots', {'leagueId': _leagueId}));
      if (!mounted) return;
      setState(() => _owned = r.i('owned'));
      if (r.i('settled') > 0) {
        ref.invalidate(leagueManageProvider(_leagueId));
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.league_sponsorSpotsAddedPlaceYour(r.i('settled')))));
      } else if (!quiet) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.league_noNewPaymentYetIt)));
      }
    } catch (_) {
      // Quietly retried next time the sheet opens.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _buy() async {
    final sp = _spots;
    final price = sp?.o('price');
    final max = sp?.i('max') ?? 8;
    if (sp?.b('walletReady') != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.league_setUpYourGroupWallet2)));
      return;
    }
    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.league_sponsorSpotsArentOnSale2)));
      return;
    }
    final qty = await showSpSheet<int>(context, builder: (_) => _BuySpotsSheet(price: price, owned: _owned, max: max));
    if (qty == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = J.of(await ref.read(leaguesRepositoryProvider).mutate('buySponsorSpots', {'leagueId': _leagueId, 'quantity': qty}));
      await launchUrl(Uri.parse(r.str('url')), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _leagueId => widget.data.o('league')!.str('id');

  Future<void> _save(List<_Sponsor> next) async {
    setState(() => _busy = true);
    final ok = await leagueAction(context, ref, 'setSponsors', {'leagueId': _leagueId, 'sponsors': [for (final s in next) _sponsorJson(s)]},
        success: context.l10n.league_sponsorsSaved, refresh: [leagueManageProvider(_leagueId)]);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _list = [...next]..sort((a, b) => a.tier == b.tier ? 0 : (a.tier == 'title' ? -1 : 1));
    });
  }

  Future<void> _edit(int? i) async {
    final titleTaken = _list.indexed.any((e) => e.$2.tier == 'title' && e.$1 != i);
    final s = await showSpSheet<_Sponsor>(context,
        builder: (_) => _SponsorEditor(
            groupId: widget.groupId,
            initial: i == null ? (name: '', url: null, logoUrl: null, tier: titleTaken ? 'partner' : 'title') : _list[i],
            titleTaken: titleTaken));
    if (s == null || !mounted) return;
    await _save(i == null ? [..._list, s] : [for (final (j, x) in _list.indexed) j == i ? s : x]);
  }

  Future<void> _reviewTerms() async {
    final ok = await showSpSheet<bool>(context, builder: (_) => _TermsSheet(leagueId: _leagueId));
    if (ok == true && mounted) {
      setState(() => _termsOk = true);
      ref.invalidate(leagueManageProvider(_leagueId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final max = _spots?.i('max') ?? 8;
    if (!_termsOk) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        SpSheetHeader(title: context.l10n.league_sponsors, icon: Icons.lock_outline_rounded),
        Text(
            context.l10n.league_showATitleSponsorPresented2,
            style: TextStyle(color: p.muted, fontSize: 13)),
        const SizedBox(height: 16),
        SpButton(label: context.l10n.league_reviewAcceptTerms, icon: Icons.fact_check_outlined, expand: true, onTap: _reviewTerms),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: context.l10n.league_sponsors,
          subtitle: context.l10n.league_theTitleSponsorShowsAs,
          icon: Icons.handshake_rounded),
      if (_suspended != null)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: p.danger.withAlpha(26), borderRadius: BorderRadius.circular(16)),
          child: Text(
              context.l10n.league_sportPadiHasSuspendedThisLeagues2(_suspended ?? ''),
              style: TextStyle(color: p.danger, fontSize: 12.5)),
        ),
      if (_list.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(context.l10n.league_noSponsorsYet, style: TextStyle(color: p.muted, fontSize: 13)),
        )
      else
        SpListCard(children: [
          for (final (i, s) in _list.indexed)
            ListTile(
              leading: _Logo(s: s, size: 38),
              title: Text(s.name, style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
              subtitle: _downReason(s) != null
                  ? Text(context.l10n.league_takenDownBySportPadi2(_downReason(s) ?? ''),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.danger, fontSize: 12))
                  : Text(s.url ?? context.l10n.league_noLink, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: _busy ? null : () => _edit(i),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_downReason(s) != null)
                  SpBadge(context.l10n.league_hidden, tone: p.danger)
                else
                  SpBadge(s.tier == 'title' ? context.l10n.league_title : context.l10n.league_partner, tone: s.tier == 'title' ? p.greenText : null),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: p.danger, size: 20),
                  onPressed: _busy ? null : () => _save([for (final (j, x) in _list.indexed) if (j != i) x]),
                ),
              ]),
            ),
        ]),
      const SizedBox(height: 10),
      Text(
          _owned > 0
              ? context.l10n.league_countPluralOneOfSpot2(_owned, _list.length, (_list.length > _owned ? context.l10n.league_sponsorsBeyondYourSpotsDont2 : ''))
              : context.l10n.league_eachSponsorTakesASponsor,
          style: TextStyle(color: p.muted, fontSize: 12.5)),
      const SizedBox(height: 12),
      if (_list.length < _owned)
        SpButton(label: context.l10n.league_addASponsor, icon: Icons.add_rounded, expand: true, onTap: _busy ? null : () => _edit(null)),
      if (_owned < max) ...[
        const SizedBox(height: 8),
        SpPill(
          label: _busy ? context.l10n.league_openingCheckout : context.l10n.league_buySponsorSpots,
          icon: Icons.credit_card_rounded,
          tone: _list.length < _owned ? SpPillTone.soft : SpPillTone.ink,
          expand: true,
          onTap: _busy ? null : _buy,
        ),
      ],
      const SizedBox(height: 6),
      TextButton(
        onPressed: _checking ? null : () => _confirm(),
        child: Text(_checking ? context.l10n.league_checkingPayment : context.l10n.league_paidAlreadyCheckPayment),
      ),
    ]);
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.s, required this.size});
  final _Sponsor s;
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final url = s.logoUrl;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: url == null ? p.surface2 : Colors.white, borderRadius: BorderRadius.circular(12)),
      child: url == null
          ? Text(s.name.isEmpty ? '?' : s.name.substring(0, s.name.length < 2 ? s.name.length : 2).toUpperCase(),
              style: TextStyle(color: p.ink, fontWeight: FontWeight.w800, fontSize: 12))
          : Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
    );
  }
}

class _SponsorEditor extends ConsumerStatefulWidget {
  const _SponsorEditor({required this.groupId, required this.initial, required this.titleTaken});
  final String groupId;
  final _Sponsor initial;
  final bool titleTaken;
  @override
  ConsumerState<_SponsorEditor> createState() => _SponsorEditorState();
}

class _SponsorEditorState extends ConsumerState<_SponsorEditor> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _url = TextEditingController(text: widget.initial.url ?? '');
  late String? _logo = widget.initial.logoUrl;
  late String _tier = widget.initial.tier;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 90);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref
          .read(eventsRepositoryProvider)
          .uploadImage(bytes, picked.mimeType ?? 'image/png', assetType: 'groupImage', scopeId: widget.groupId);
      if (mounted) setState(() => _logo = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final url = _url.text.trim();
    final validUrl = url.isEmpty || RegExp(r'^https?://\S+\.\S+').hasMatch(url);
    final current = (name: _name.text.trim(), url: url.isEmpty ? null : url, logoUrl: _logo, tier: _tier);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(title: widget.initial.name.isEmpty ? context.l10n.league_addASponsor : context.l10n.league_editSponsor, icon: Icons.handshake_rounded),
      Row(children: [
        _Logo(s: current, size: 56),
        const SizedBox(width: 12),
        SpPill(
          label: _uploading ? context.l10n.league_uploading : (_logo == null ? context.l10n.league_uploadLogo : context.l10n.league_changeLogo),
          icon: Icons.add_photo_alternate_outlined,
          tone: SpPillTone.soft,
          height: 36,
          onTap: _uploading ? null : _pick,
        ),
        if (_logo != null)
          IconButton(icon: Icon(Icons.close_rounded, color: p.muted), onPressed: () => setState(() => _logo = null)),
      ]),
      FieldLabel(context.l10n.league_name),
      TextField(controller: _name, maxLength: 60, onChanged: (_) => setState(() {}), decoration: fieldDeco(context, context.l10n.league_sponsorName)),
      FieldLabel(context.l10n.league_websiteOptional),
      TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
          decoration: fieldDeco(context, 'https://their-site.com')),
      if (!validUrl)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(context.l10n.league_useAFullWebAddress, style: TextStyle(color: p.danger, fontSize: 12)),
        ),
      FieldLabel(context.l10n.league_type),
      Wrap(spacing: 8, children: [
        ChoiceChip(
          label: Text(widget.titleTaken ? context.l10n.league_titleSponsorTaken : context.l10n.league_titleSponsor),
          selected: _tier == 'title',
          onSelected: widget.titleTaken ? null : (_) => setState(() => _tier = 'title'),
        ),
        ChoiceChip(label: Text(context.l10n.league_partner), selected: _tier == 'partner', onSelected: (_) => setState(() => _tier = 'partner')),
      ]),
      const SizedBox(height: 16),
      SpButton(
        label: context.l10n.league_saveSponsor,
        expand: true,
        onTap: _uploading || current.name.isEmpty || !validUrl ? null : () => Navigator.of(context).pop(current),
      ),
    ]);
  }
}

/// The Sponsorship Terms (served by the API so web and app show the same
/// version), scrolled through, with an explicit "I agree". Pops true once
/// accepted.
class _TermsSheet extends ConsumerStatefulWidget {
  const _TermsSheet({required this.leagueId});
  final String leagueId;
  @override
  ConsumerState<_TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends ConsumerState<_TermsSheet> {
  J? _terms;
  bool _agree = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(leaguesRepositoryProvider).obj('sponsorTerms', {'leagueId': widget.leagueId});
      if (mounted) setState(() => _terms = t);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = _terms;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: t?.str('title', context.l10n.league_sponsorshipTerms) ?? context.l10n.league_sponsorshipTerms,
          subtitle: context.l10n.league_pleaseReadTheseBeforeBuying,
          icon: Icons.fact_check_outlined),
      if (_error != null)
        Text(_error!, style: TextStyle(color: p.danger))
      else if (t == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else ...[
        Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
          decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
          child: ListView(padding: const EdgeInsets.all(14), shrinkWrap: true, children: [
            Text(t.str('intro'), style: TextStyle(color: p.ink, fontSize: 13, height: 1.4)),
            for (final s in t.list('sections')) ...[
              const SizedBox(height: 12),
              Text(s.str('heading'), style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w800)),
              for (final para in s.strs('paragraphs'))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(para, style: TextStyle(color: p.ink, fontSize: 13, height: 1.4)),
                ),
              for (final b in s.strs('bullets'))
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8),
                  child: Text('•  $b', style: TextStyle(color: p.ink, fontSize: 13, height: 1.4)),
                ),
            ],
            const SizedBox(height: 10),
            Text(context.l10n.league_versionUpdated(t.str('version'), t.str('updated')), style: TextStyle(color: p.muted, fontSize: 11.5)),
          ]),
        ),
        const SizedBox(height: 10),
        Text(
            context.l10n.league_inShortSportPadiMayStill,
            style: TextStyle(color: p.muted, fontSize: 12)),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _agree,
          onChanged: (v) => setState(() => _agree = v ?? false),
          title: Text(context.l10n.league_iHaveReadAndAgree,
              style: TextStyle(color: p.ink, fontSize: 13)),
        ),
        SpButton(
          label: context.l10n.league_acceptAndContinue,
          expand: true,
          onTap: !_agree || _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await leagueAction(context, ref, 'acceptSponsorTerms',
                      {'leagueId': widget.leagueId, 'version': t.str('version'), 'agree': true},
                      success: context.l10n.league_sponsorshipTermsAccepted);
                  if (!mounted) return;
                  setState(() => _busy = false);
                  if (ok) Navigator.of(this.context).pop(true);
                },
        ),
      ],
    ]);
  }
}

/// How many spots to buy; returns the quantity.
class _BuySpotsSheet extends StatefulWidget {
  const _BuySpotsSheet({required this.price, required this.owned, required this.max});
  final J price;
  final int owned;
  final int max;
  @override
  State<_BuySpotsSheet> createState() => _BuySpotsSheetState();
}

class _BuySpotsSheetState extends State<_BuySpotsSheet> {
  int _qty = 1;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final room = (widget.max - widget.owned).clamp(0, widget.max);
    final unit = widget.price.i('priceMinor');
    final cur = widget.price.str('currency');
    final exp = widget.price.i('exponent');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: context.l10n.league_buySponsorSpots,
          subtitle: context.l10n.league_oneSpotOneSponsorOn2,
          icon: Icons.credit_card_rounded),
      if (room == 0)
        Text(context.l10n.league_thisSeasonAlreadyHasThe(widget.max), style: TextStyle(color: p.muted))
      else ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.l10n.league_perSpot(spotMoney(unit, cur, exp)), style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
                Text(context.l10n.league_youHaveUpToA(widget.owned, widget.max), style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
            ),
            IconButton(onPressed: _qty <= 1 ? null : () => setState(() => _qty--), icon: const Icon(Icons.remove_circle_outline_rounded)),
            Text('$_qty', style: TextStyle(color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            IconButton(onPressed: _qty >= room ? null : () => setState(() => _qty++), icon: const Icon(Icons.add_circle_outline_rounded)),
          ]),
        ),
        const SizedBox(height: 14),
        SpButton(label: context.l10n.league_pay2(spotMoney(unit * _qty, cur, exp)), icon: Icons.lock_rounded, expand: true, onTap: () => Navigator.of(context).pop(_qty)),
        const SizedBox(height: 6),
        Text(
            context.l10n.league_checkoutOpensInYourBrowser,
            style: TextStyle(color: p.muted, fontSize: 12)),
      ],
    ]);
  }
}

/* ─── Match tickets ────────────────────────────────────────────────────── */

Future<void> showTicketsSheet(BuildContext context, WidgetRef ref, {required J data}) =>
    showSpSheet<void>(context, builder: (_) => _TicketsSheet(data: data));

class _TicketsSheet extends ConsumerStatefulWidget {
  const _TicketsSheet({required this.data});
  final J data;
  @override
  ConsumerState<_TicketsSheet> createState() => _TicketsSheetState();
}

class _TicketsSheetState extends ConsumerState<_TicketsSheet> {
  J? get _t => widget.data.o('ticketing');
  J? get _wallet => widget.data.o('wallet');
  int get _exp => _wallet?.i('exponent') ?? 2;
  late bool _on = _t?.b('enabled') ?? false;
  late final _title = TextEditingController(text: _t?.s('title') ?? context.l10n.league_matchTicket);
  late final _price = TextEditingController(
      text: _t == null ? '' : (_t!.i('price') / _pow(_exp)).toStringAsFixed(_exp).replaceFirst(RegExp(r'\.?0+$'), ''));
  late final _capacity = TextEditingController(text: _t?.iOrNull('capacity')?.toString() ?? '');
  late final _days = TextEditingController(text: _t?.iOrNull('salesOpenDaysBefore')?.toString() ?? '');
  late final _note = TextEditingController(text: _t?.s('description') ?? '');
  bool _busy = false;

  static int _pow(int e) {
    var x = 1;
    for (var i = 0; i < e; i++) {
      x *= 10;
    }
    return x;
  }

  String get _leagueId => widget.data.o('league')!.str('id');

  @override
  void dispose() {
    for (final c in [_title, _price, _capacity, _days, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final w = _wallet;
    final minor = ((double.tryParse(_price.text.trim()) ?? 0) * _pow(_exp)).round();
    final valid = !_on || (minor > 0 && _title.text.trim().isNotEmpty);
    final tk = widget.data.o('tickets');
    final missing = (tk?.i('published') ?? 0) - (tk?.i('withTicket') ?? 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: context.l10n.league_matchTickets,
          subtitle: context.l10n.league_eachFixtureGetsASpectator2,
          icon: Icons.confirmation_number_outlined),
      if (w == null)
        Text(context.l10n.league_activateYourGroupWalletFirst,
            style: TextStyle(color: p.muted, fontSize: 13))
      else ...[
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.league_sellMatchTickets, style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
          value: _on,
          onChanged: (v) => setState(() => _on = v),
        ),
        if (_on) ...[
          FieldLabel(context.l10n.league_ticketName),
          TextField(controller: _title, maxLength: 60, onChanged: (_) => setState(() {}), decoration: fieldDeco(context, context.l10n.league_matchTicket)),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FieldLabel(context.l10n.league_price2(w.str('currency'))),
                TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: fieldDeco(context, '0.00')),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FieldLabel(context.l10n.league_capacityOptional),
                TextField(controller: _capacity, keyboardType: TextInputType.number, decoration: fieldDeco(context, context.l10n.league_noLimit)),
              ]),
            ),
          ]),
          FieldLabel(context.l10n.league_salesOpenDaysBeforeOptional2),
          TextField(controller: _days, keyboardType: TextInputType.number, decoration: fieldDeco(context, context.l10n.league_straightAway)),
          FieldLabel(context.l10n.league_noteOnTheTicketOptional),
          TextField(controller: _note, maxLength: 500, decoration: fieldDeco(context, context.l10n.league_gatesOpen30MinutesBefore)),
        ],
        const SizedBox(height: 14),
        SpButton(
          label: context.l10n.league_save,
          expand: true,
          onTap: _busy || !valid
              ? null
              : () async {
                  setState(() => _busy = true);
                  final t = _t;
                  final ok = await leagueAction(context, ref, 'setTicketing', {
                    'leagueId': _leagueId,
                    'ticketing': _on
                        ? {
                            'enabled': true,
                            'title': _title.text.trim(),
                            'price': minor,
                            'capacity': int.tryParse(_capacity.text.trim()),
                            'description': _note.text.trim().isEmpty ? null : _note.text.trim(),
                            'salesOpenDaysBefore': int.tryParse(_days.text.trim()),
                          }
                        : t == null
                            ? null
                            : {...t.raw, 'enabled': false},
                  }, success: _on ? context.l10n.league_matchTicketsSaved : context.l10n.league_matchTicketsOff, refresh: [leagueManageProvider(_leagueId)]);
                  if (!mounted) return;
                  setState(() => _busy = false);
                  if (ok) Navigator.of(this.context).pop();
                },
        ),
        if (_t?.b('enabled') == true && widget.data.o('league')?.s('status') != 'draft' && missing > 0) ...[
          const SizedBox(height: 8),
          SpPill(
            label: context.l10n.league_addToPublishedFixtures(missing),
            tone: SpPillTone.soft,
            expand: true,
            onTap: _busy
                ? null
                : () => leagueAction(context, ref, 'applyTickets', {'leagueId': _leagueId},
                    success: context.l10n.league_ticketsAdded, refresh: [leagueManageProvider(_leagueId)]),
          ),
        ],
      ],
    ]);
  }
}
