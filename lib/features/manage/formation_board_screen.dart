import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/squad_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

class _Pos {
  _Pos(this.x, this.y, this.starter);
  double x;
  double y;
  bool starter;
}

double _clamp(double v) => v < 4 ? 4 : (v > 96 ? 96 : v);

// Web findOpenSpot: candidate slots scanned rows-then-columns so a fielded
// bench player lands in open space instead of stacking in the middle.
const _spotXs = [18.0, 34.0, 50.0, 66.0, 82.0];
const _spotYs = [80.0, 66.0, 52.0, 38.0, 24.0, 88.0, 12.0];
const _minSpacing = 13.0;

(double, double) _findOpenSpot(List<(double, double)> occupied) {
  bool clear(double x, double y, double d) => occupied.every((o) {
        final dx = o.$1 - x;
        final dy = o.$2 - y;
        return (dx * dx + dy * dy) >= d * d;
      });
  for (final y in _spotYs) {
    for (final x in _spotXs) {
      if (clear(x, y, _minSpacing)) return (x, y);
    }
  }
  for (var gy = 12.0; gy <= 88; gy += 6) {
    for (var gx = 12.0; gx <= 88; gx += 6) {
      if (clear(gx, gy, 6)) return (gx, gy);
    }
  }
  return (50, 50);
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return [
    for (final p in parts.take(2))
      if (p.isNotEmpty) p[0].toUpperCase()
  ].join();
}

Color _hex(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v != null ? Color(v) : fallback;
}

/// Pitch/court markings by surface — a port of the web SurfaceMarkings SVG
/// (0-100 box, y=0 own end; preserveAspectRatio "none" → scale x/y freely).
class _MarkingsPainter extends CustomPainter {
  const _MarkingsPainter(this.surface);
  final String? surface;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    double sx(double v) => v / 100 * size.width;
    double sy(double v) => v / 100 * size.height;
    Rect box(double x, double y, double w, double h) =>
        Rect.fromLTWH(sx(x), sy(y), sx(w), sy(h));

    if (surface == 'court') {
      canvas.drawRect(box(3, 3, 94, 94), line);
      canvas.drawLine(Offset(sx(3), sy(50)), Offset(sx(97), sy(50)), line);
      canvas.drawOval(box(41, 41, 18, 18), line);
      return;
    }
    if (surface == 'diamond') {
      final outer = Path()
        ..moveTo(sx(50), sy(8))
        ..lineTo(sx(82), sy(45))
        ..lineTo(sx(50), sy(82))
        ..lineTo(sx(18), sy(45))
        ..close();
      final inner = Path()
        ..moveTo(sx(50), sy(20))
        ..lineTo(sx(68), sy(45))
        ..lineTo(sx(50), sy(60))
        ..lineTo(sx(32), sy(45))
        ..close();
      canvas.drawPath(outer, line);
      canvas.drawPath(inner, line);
      return;
    }
    // Default: soccer pitch (portrait — own goal at the bottom).
    canvas.drawRect(box(3, 3, 94, 94), line);
    canvas.drawLine(Offset(sx(3), sy(50)), Offset(sx(97), sy(50)), line);
    canvas.drawOval(box(41, 41, 18, 18), line);
    canvas.drawCircle(Offset(sx(50), sy(50)), 1.6, Paint()..color = line.color);
    // bottom (own) box + goal area
    canvas.drawRect(box(30, 88, 40, 9), line);
    canvas.drawRect(box(40, 94, 20, 3), line);
    // top (opponent) box + goal area
    canvas.drawRect(box(30, 3, 40, 9), line);
    canvas.drawRect(box(40, 3, 20, 3), line);
  }

  @override
  bool shouldRepaint(_MarkingsPainter old) => old.surface != surface;
}

/// Web pitch background: repeating mowed-grass stripes
/// (repeating-linear-gradient 0deg, #157a3f 0-10%, #17864a 10-20%).
class _StripesPainter extends CustomPainter {
  const _StripesPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final a = Paint()..color = const Color(0xFF157A3F);
    final b = Paint()..color = const Color(0xFF17864A);
    final band = size.height / 10;
    for (var i = 0; i < 10; i++) {
      canvas.drawRect(
          Rect.fromLTWH(0, i * band, size.width, band), i.isEven ? a : b);
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) => false;
}

/// The interactive formation board — a faithful port of the web
/// FormationPitch: category-driven surface markings, kit-coloured draggable
/// tokens with captain badge and × bench control, position-aware bench chips,
/// formation switcher and debounced auto-save.
/// The pitch/court board. Two data sources:
///   • a TOURNAMENT SQUAD ([eventId] set): the accepted players for that
///     event; placements save to the squad — the only place formations live
///     now (there is no general team formation any more);
///   • legacy team mode ([eventId] null): read-only view of the old roster
///     placements, kept so nothing crashes on old links.
class FormationBoardScreen extends ConsumerStatefulWidget {
  const FormationBoardScreen({super.key, required this.teamId, this.eventId});
  final String teamId;
  final String? eventId;
  @override
  ConsumerState<FormationBoardScreen> createState() =>
      _FormationBoardScreenState();
}

class _FormationBoardScreenState extends ConsumerState<FormationBoardScreen> {
  TeamDetail? _team;
  String? _tournamentTeamId; // squad mode only
  final Map<String, _Pos> _pos = {};
  String? _formationName;
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Squad → the TeamDetail shape the board renders (memberId = squad row id).
  TeamDetail _fromSquad(TournamentSquad sq) {
    final cfg = Map<String, dynamic>.from(sq.formationConfig);
    return TeamDetail(
      id: sq.teamId,
      name: sq.teamName,
      username: sq.teamUsername,
      logoUrl: sq.teamLogoUrl,
      kitPrimary: sq.kitPrimary,
      kitSecondary: sq.kitSecondary,
      groupId: sq.teamGroupId,
      formationName: sq.formationName,
      canManage: sq.canManage && !sq.isOver,
      formation: FormationConfig.fromJson(cfg),
      members: [
        for (final m in sq.accepted)
          TeamMember(
            memberId: m.id,
            playerId: m.playerId,
            displayName: m.name,
            username: m.profile?.username,
            avatarUrl: m.profile?.avatarUrl,
            jerseyNumber: m.jerseyNumber,
            positions: m.positions,
            isStarter: m.isStarter,
            isCaptain: m.isCaptain,
            posX: m.posX,
            posY: m.posY,
          ),
      ],
    );
  }

  Future<void> _load() async {
    try {
      final TeamDetail t;
      if (widget.eventId != null) {
        final sq = await ref.read(
            tournamentSquadProvider('${widget.eventId}|${widget.teamId}')
                .future);
        _tournamentTeamId = sq.tournamentTeamId;
        t = _fromSquad(sq);
      } else {
        // Legacy: view-only (formations are per tournament now).
        final base = await ref.read(teamDetailProvider(widget.teamId).future);
        t = TeamDetail(
          id: base.id,
          name: base.name,
          username: base.username,
          logoUrl: base.logoUrl,
          kitPrimary: base.kitPrimary,
          kitSecondary: base.kitSecondary,
          groupId: base.groupId,
          formationName: base.formationName,
          members: base.members,
          formation: base.formation,
          canManage: false,
        );
      }
      _pos.clear();
      for (final m in t.members) {
        // Unplaced starters default to centre so they appear on the pitch
        // (and can be dragged) rather than silently sitting on the bench.
        _pos[m.memberId] = _Pos(m.posX ?? 50, m.posY ?? 50, m.isStarter);
      }
      final forms = t.formation.formations;
      setState(() {
        _team = t;
        final defName = t.formationName ?? t.formation.defaultFormationName;
        _formationName = forms.any((f) => f.name == defName)
            ? defName
            : (forms.isNotEmpty ? forms.first.name : null);
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  bool get _readOnly => !(_team?.canManage ?? false);

  void _markDirty() {
    if (_readOnly) return;
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
    setState(() {});
  }

  Future<void> _save() async {
    if (_readOnly) return;
    final team = _team;
    if (team == null) return;
    setState(() => _saving = true);
    final placements = [
      for (final m in team.members)
        if (_pos[m.memberId]?.starter == true)
          {
            'memberId': m.memberId,
            'posX': _pos[m.memberId]!.x,
            'posY': _pos[m.memberId]!.y,
            'isStarter': true,
          }
        else
          {
            'memberId': m.memberId,
            'posX': null,
            'posY': null,
            'isStarter': false
          },
    ];
    try {
      final eventId = widget.eventId;
      final ttId = _tournamentTeamId;
      if (eventId == null || ttId == null) return; // legacy view is read-only
      await ref.read(tournamentsRepositoryProvider).setSquadFormation(
        eventId,
        ttId,
        formationName: _formationName,
        placements: [
          for (final pl in placements)
            {
              'squadId': pl['memberId'],
              'isStarter': pl['isStarter'],
              'posX': pl['posX'],
              'posY': pl['posY'],
            },
        ],
      );
      ref.invalidate(tournamentSquadProvider('$eventId|${widget.teamId}'));
      if (mounted) {
        setState(() {
          _dirty = false;
          _saving = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _dirty = false;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  int get _starterCount => _pos.values.where((p) => p.starter).length;

  void _bench(String id) {
    setState(() => _pos[id]?.starter = false);
    _markDirty();
  }

  /// The token's × — offer Bench or Substitute (web parity).
  Future<void> _tokenMenu(TeamMember m) async {
    final p = context.palette;
    final choice = await showSpSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(m.displayName,
              style: TextStyle(
                  color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ListTile(
            dense: true,
            leading: Icon(Icons.group_outlined, size: 20, color: p.muted),
            title: Text('Bench', style: TextStyle(color: p.ink, fontSize: 14)),
            onTap: () => Navigator.pop(ctx, 'bench'),
          ),
          ListTile(
            dense: true,
            leading: Icon(Icons.login_rounded, size: 20, color: p.muted),
            title: Text('Sub', style: TextStyle(color: p.ink, fontSize: 14)),
            subtitle: Text('Bring a bench player on in this spot',
                style: TextStyle(color: p.muted, fontSize: 11)),
            onTap: () => Navigator.pop(ctx, 'sub'),
          ),
          ListTile(
            dense: true,
            leading: Icon(Icons.swap_horiz_rounded, size: 20, color: p.muted),
            title: Text('Swap', style: TextStyle(color: p.ink, fontSize: 14)),
            subtitle: Text('Switch positions with a pitch player',
                style: TextStyle(color: p.muted, fontSize: 11)),
            onTap: () => Navigator.pop(ctx, 'swap'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'bench') {
      _bench(m.memberId);
    } else if (choice == 'sub') {
      await _pickSub(m, fromBench: true);
    } else if (choice == 'swap') {
      await _pickSub(m, fromBench: false);
    }
  }

  /// Pick who comes in for [source]. [fromBench] = Sub (a bench player sends
  /// them off and takes their exact spot); otherwise Swap (a pitch player
  /// switches positions with them).
  Future<void> _pickSub(TeamMember source, {required bool fromBench}) async {
    final team = _team;
    if (team == null) return;
    final p = context.palette;
    final candidates = fromBench
        ? [
            for (final x in team.members)
              if (_pos[x.memberId]?.starter != true) x
          ]
        : [
            for (final x in team.members)
              if (x.memberId != source.memberId &&
                  _pos[x.memberId]?.starter == true)
                x
          ];

    Widget row(BuildContext ctx, TeamMember x) => ListTile(
          dense: true,
          title: Text(x.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.ink, fontSize: 14)),
          trailing: x.positions.isNotEmpty
              ? Text(x.positions.first,
                  style: TextStyle(color: p.muted, fontSize: 12))
              : null,
          onTap: () => Navigator.pop(ctx, x.memberId),
        );
    Widget header(String t) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(t.toUpperCase(),
              style: TextStyle(
                  color: p.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
        );

    final targetId = await showSpSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${fromBench ? 'Sub' : 'Swap'} ${source.displayName}',
              style: TextStyle(
                  color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
          header(fromBench
              ? 'From the bench — takes their spot'
              : 'On the pitch — switch positions'),
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  fromBench
                      ? 'The bench is empty.'
                      : 'No other players on the pitch.',
                  style: TextStyle(color: p.muted, fontSize: 12)),
            )
          else
            for (final x in candidates) row(ctx, x),
        ],
      ),
    );
    if (targetId == null || !mounted) return;
    final src = _pos[source.memberId];
    final tgt = _pos[targetId];
    if (src == null || tgt == null) return;
    setState(() {
      if (tgt.starter) {
        // Both on the pitch: switch positions.
        final tx = tgt.x;
        final ty = tgt.y;
        tgt.x = src.x;
        tgt.y = src.y;
        src.x = tx;
        src.y = ty;
      } else {
        // Bench sub: source goes off; sub comes on in the exact same spot.
        tgt.starter = true;
        tgt.x = src.x;
        tgt.y = src.y;
        src.starter = false;
      }
    });
    _markDirty();
  }

  void _toPitch(String id) {
    final max = _team?.formation.maxStarters ?? 11;
    if (_starterCount >= max) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('At most $max on the field.')));
      return;
    }
    // Position-aware placement (web): first open lattice slot, never on top
    // of a fielded player.
    final occupied = [
      for (final e in _pos.entries)
        if (e.key != id && e.value.starter) (e.value.x, e.value.y)
    ];
    final spot = _findOpenSpot(occupied);
    setState(() {
      final p = _pos[id];
      if (p != null) {
        p.starter = true;
        p.x = spot.$1;
        p.y = spot.$2;
      }
    });
    _markDirty();
  }

  // Switch to a named formation: reposition ONLY the players already on the
  // pitch into the new shape (bench untouched). Slots are matched by the
  // players' preferred positions first, then filled in order — web logic.
  void _applyFormation(String name) {
    if (_readOnly) return;
    final team = _team;
    if (team == null) return;
    final slots = team.formation.formations
        .where((f) => f.name == name)
        .expand((f) => f.slots)
        .toList();
    if (slots.isEmpty) return;
    final starters =
        team.members.where((m) => _pos[m.memberId]?.starter == true).toList();
    final remaining = starters.map((m) => m.memberId).toSet();
    final byId = {for (final m in starters) m.memberId: m};
    final cap = [slots.length, team.formation.maxStarters, starters.length]
        .reduce((a, b) => a < b ? a : b);
    final use = slots.take(cap).toList();
    final assign = <String, FormationSlot>{};
    final open = <FormationSlot>[];
    for (final s in use) {
      String? pick;
      for (final id in remaining) {
        if (byId[id]!.positions.contains(s.role)) {
          pick = id;
          break;
        }
      }
      if (pick != null) {
        assign[pick] = s;
        remaining.remove(pick);
      } else {
        open.add(s);
      }
    }
    final leftover = remaining.toList();
    for (var i = 0; i < open.length && i < leftover.length; i++) {
      assign[leftover[i]] = open[i];
    }
    setState(() {
      _formationName = name;
      assign.forEach((id, s) {
        final p = _pos[id];
        if (p != null) {
          p.x = s.x;
          p.y = s.y;
          p.starter = true;
        }
      });
    });
    _markDirty();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final team = _team;
    if (team == null) {
      return Scaffold(
        appBar:
            AppBar(leading: const SpLeading(), title: const Text('Formation')),
        body: Center(child: Text(_error ?? 'Could not load the team.')),
      );
    }
    if (!team.formation.needsFormation) {
      return Scaffold(
        appBar:
            AppBar(leading: const SpLeading(), title: const Text('Formation')),
        body: const Center(child: Text('This sport has no formation board.')),
      );
    }
    final surface = team.formation.surface;
    final forms = team.formation.formations;
    final bench =
        team.members.where((m) => _pos[m.memberId]?.starter != true).toList();
    final tokenColor = _hex(team.kitPrimary, const Color(0xFF16A34A));
    final tokenText = _hex(team.kitSecondary, Colors.white);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          children: [
            SpHeader(title: 'Formation', subtitle: team.name),
            const SizedBox(height: 16),
            // Header row — how full the pitch is, the shape switcher, saved.
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_starterCount/${team.formation.maxStarters}',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 22,
                              height: 1.1,
                              fontWeight: FontWeight.w800)),
                      Text('on the pitch',
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ]),
              ),
              if (!_readOnly && forms.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: cardShadow(context),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _formationName,
                      hint: Text('Formation…',
                          style: TextStyle(color: p.muted, fontSize: 12)),
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                      items: [
                        for (final f in forms)
                          DropdownMenuItem(value: f.name, child: Text(f.name))
                      ],
                      onChanged: (v) {
                        if (v != null) _applyFormation(v);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (!_readOnly)
                Row(children: [
                  if (_saving || _dirty)
                    const SizedBox(
                        height: 13,
                        width: 13,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(Icons.check_rounded, size: 15, color: p.accent),
                  const SizedBox(width: 4),
                  Text(_saving || _dirty ? 'Saving…' : 'Saved',
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
            ]),
            const SizedBox(height: 10),

            // The pitch/court/diamond — surface picked by the sport category.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 384),
                child: AspectRatio(
                  aspectRatio: 68 / 100,
                  child: LayoutBuilder(builder: (context, box) {
                    final w = box.maxWidth;
                    final h = box.maxHeight;
                    return Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Stack(children: [
                        const Positioned.fill(
                            child: CustomPaint(painter: _StripesPainter())),
                        Positioned.fill(
                            child: CustomPaint(
                                painter: _MarkingsPainter(surface))),
                        for (final m in team.members)
                          if (_pos[m.memberId]?.starter == true)
                            _token(context, m, w, h, tokenColor, tokenText),
                      ]),
                    );
                  }),
                ),
              ),
            ),

            // Bench — web: pill chips, tap to field.
            const SizedBox(height: 14),
            Row(children: [
              Icon(Icons.group_outlined, size: 14, color: p.muted),
              const SizedBox(width: 5),
              Text('BENCH (${bench.length})',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
            ]),
            const SizedBox(height: 8),
            if (bench.isEmpty)
              Text("Everyone's on the field.",
                  style: TextStyle(color: p.muted, fontSize: 12))
            else
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in bench)
                  _benchChip(context, m, tokenColor, tokenText),
              ]),
            if (!_readOnly) ...[
              const SizedBox(height: 8),
              Text(
                surface == 'pitch' || surface == null
                    ? 'Tap a bench player to field them, drag tokens to position, tap × to bench or substitute.'
                    : 'Tap to field, drag to position, × to bench or substitute.',
                style: TextStyle(color: p.muted, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A placed player: 32px kit-coloured disc (number or initials), captain
  /// badge, × bench control, "POS · First" label — the web token.
  Widget _token(BuildContext context, TeamMember m, double w, double h,
      Color tokenColor, Color tokenText) {
    final st = _pos[m.memberId]!;
    const groupW = 72.0;
    final label = [
      if (m.positions.isNotEmpty) m.positions.first,
      m.displayName.split(' ').first,
    ].join(' · ');

    return Positioned(
      left: (st.x / 100) * w - groupW / 2,
      top: (st.y / 100) * h - 16,
      width: groupW,
      child: GestureDetector(
        onPanUpdate: _readOnly
            ? null
            : (d) {
                setState(() {
                  st.x = _clamp(st.x + d.delta.dx / w * 100);
                  st.y = _clamp(st.y + d.delta.dy / h * 100);
                });
                _dirty = true;
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 600), _save);
              },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 44,
            height: 36,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 6,
                top: 2,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokenColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: tokenText, width: 2),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: Text(
                    m.jerseyNumber?.toString() ?? _initials(m.displayName),
                    style: TextStyle(
                        color: tokenText,
                        fontSize: 11,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (m.isCaptain)
                Positioned(
                  left: 0,
                  top: -4,
                  child: Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF5A70A),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('C',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              if (!_readOnly)
                Positioned(
                  right: 0,
                  top: -4,
                  child: GestureDetector(
                    onTap: () => _tokenMenu(m),
                    child: Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.palette.surface,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 3),
                        ],
                      ),
                      child: Icon(Icons.close,
                          size: 10, color: context.palette.danger),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 1),
          Container(
            constraints: const BoxConstraints(maxWidth: groupW),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(0, 0, 0, 0.45),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }

  /// Bench pill — mini kit token + first name + position (web chip).
  Widget _benchChip(
      BuildContext context, TeamMember m, Color tokenColor, Color tokenText) {
    final p = context.palette;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _readOnly ? null : () => _toPitch(m.memberId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: tokenColor, shape: BoxShape.circle),
              child: Text(
                m.jerseyNumber?.toString() ?? _initials(m.displayName),
                style: TextStyle(
                    color: tokenText,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              m.displayName.split(' ').first,
              style: TextStyle(color: p.ink, fontSize: 12),
            ),
            if (m.positions.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(m.positions.first,
                  style: TextStyle(color: p.muted, fontSize: 11)),
            ],
          ]),
        ),
      ),
    );
  }
}
