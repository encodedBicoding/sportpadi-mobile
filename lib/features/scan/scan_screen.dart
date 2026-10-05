import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/data/tickets/tickets_repository.dart';
import 'package:sportpadi_mobile/data/wards/ward_models.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart';
import 'package:sportpadi_mobile/features/wards/ward_pickers.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart' show fmtInstant;
import 'package:sportpadi_mobile/shared/format/parse.dart' show parseDate;
import 'package:sportpadi_mobile/shared/widgets/sheet_scroll.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/ads/admob.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

const _mint = Color(0xFF6EDC9E);

/// One scanner for both QR kinds:
///  - event check-in QRs (a player checks themselves in), and
///  - ticket QRs (TKT-…): an organizer validates a holder at the gate.
///
/// 2026 design, matching web /scan: header, dark "Check in to an event" card
/// with a white "Open scanner" pill, a note for organisers validating tickets,
/// numbered "How it works" steps. The camera view is full-bleed black with a
/// mint aiming frame, and every result lands in one bottom sheet (big status
/// circle, message, the check-in reward in a green block, pill actions).
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

enum _Tone { success, warning, error }

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handling = false;
  bool _scanning = false;
  bool _torch = false;
  String? _lastCode;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openScanner() {
    setState(() => _scanning = true);
    // Restart after a previous stop; harmless if fresh.
    _controller.start().catchError((_) {});
  }

  void _closeScanner() {
    _controller.stop();
    setState(() {
      _scanning = false;
      _torch = false;
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw =
        capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (raw == null || raw.isEmpty || raw == _lastCode) return;
    _lastCode = raw;
    setState(() => _handling = true);
    await _controller.stop();
    try {
      if (raw.startsWith('TKT-')) {
        // A holder's ticket QR — gate validation (organizer flow).
        final res = await ref.read(ticketsRepositoryProvider).redeem(raw);
        if (!mounted) return;
        await _showRedeemResult(res);
      } else {
        // An event's check-in QR — self check-in (player flow). Guardians
        // first say who's checking in: themselves and/or their wards (A8).
        final wards = await _myWards();
        if (!mounted) return;
        if (wards.isEmpty) {
          final res = await ref.read(eventsRepositoryProvider).checkInByQr(raw);
          if (!mounted) return;
          await _showCheckInResult(res);
        } else if (!await _checkInSeveral(raw, wards)) {
          // "Who's checking in?" was dismissed: close the camera, so the
          // same QR (still in view) doesn't pop the sheet straight back up.
          if (!mounted) return;
          setState(() => _handling = false);
          _lastCode = null;
          _closeScanner();
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        await _showSheet(
          tone: _Tone.error,
          head: raw.startsWith('TKT-') ? 'Could not verify' : 'Check-in failed',
          body: '$e'.replaceFirst('Exception: ', ''),
        );
      }
    }
    if (!mounted) return;
    setState(() => _handling = false);
    _lastCode = null;
    if (_scanning) await _controller.start();
  }

  /// My wards, or none when the list can't be loaded — a failed lookup must
  /// never block my own check-in. The screen keeps [myWardsProvider] warm
  /// (see build), so this is normally the cached value, not a round-trip.
  Future<List<Ward>> _myWards() async {
    final cached = ref.read(myWardsProvider).valueOrNull;
    if (cached != null) return cached.wards;
    try {
      return (await ref.read(wardsRepositoryProvider).mine()).wards;
    } catch (_) {
      return const [];
    }
  }

  /// Guardian flow: pick who's checking in, then check each person in one
  /// after the other and show how each went. "Me only" goes through the
  /// original single-person flow ([_showCheckInResult]: the organiser CTA,
  /// the reward, the progress refresh). Returns false when the picker was
  /// dismissed without a choice.
  Future<bool> _checkInSeveral(String qrCode, List<Ward> wards) async {
    final who = await showWhoIsCheckingInSheet(context, wards: wards);
    if (!mounted) return true;
    if (who == null || who.isEmpty) return false;
    final repo = ref.read(eventsRepositoryProvider);
    if (who.length == 1 && who.first.id == null) {
      final res = await repo.checkInByQr(qrCode);
      if (!mounted) return true;
      await _showCheckInResult(res);
      return true;
    }
    final results = <CheckinOutcome>[];
    Map<String, dynamic>? mine;
    for (final person in who) {
      final isMe = person.id == null;
      try {
        final res = await repo.checkInByQr(qrCode, forPlayerId: person.id);
        if (isMe) mine = res;
        results
            .add(CheckinOutcome.fromResult(res, name: person.name, isMe: isMe));
      } catch (e) {
        results.add(CheckinOutcome.failed(
            name: person.name,
            isMe: isMe,
            message: '$e'.replaceFirst('Exception: ', '')));
      }
    }
    if (!mounted) return true;
    // Refresh whatever event screens (and Home) are behind the scanner.
    ref.invalidate(eventDetailProvider);
    ref.invalidate(myFeedProvider);
    // My own check-in's reward moves "Your week" — same rule as the
    // single-person flow.
    final myReward =
        mine != null && mine['status'] == 'checked_in' && mine['reward'] is Map
            ? Map<String, dynamic>.from(mine['reward'] as Map)
            : null;
    if (myReward != null && ((myReward['xp'] as num?)?.toInt() ?? 0) > 0) {
      ref.invalidate(yourWeekProvider);
      ref.invalidate(myProgressionProvider);
    }
    if (results.any((r) => r.ok)) HapticFeedback.mediumImpact();
    final action = await showCheckinResultsSheet(context, results: results);
    if (!mounted) return true;
    switch (action) {
      case CheckinSheetAction.done:
        context.pop();
      case CheckinSheetAction.openFines:
        // A ward's fine blocked them: their guardian pays it on Fines. Close
        // the camera first so it doesn't keep scanning underneath.
        _closeScanner();
        context.push('/fines');
      case CheckinSheetAction.scanAgain:
        break;
    }
    return true;
  }

  Future<void> _showRedeemResult(Map<String, dynamic> res) async {
    final ok = res['ok'] == true;
    final title = res['ticketTitle'] as String? ?? 'Ticket';
    if (ok) {
      HapticFeedback.mediumImpact();
      await _showSheet(
        tone: _Tone.success,
        head: 'Valid — checked in',
        body: '$title\nThe holder is in.',
      );
      return;
    }
    final reason = res['reason'] as String? ?? '';
    if (reason == 'already') {
      final at = res['redeemedAt'] as String?;
      final when = at != null ? DateTime.tryParse(at)?.toLocal() : null;
      await _showSheet(
        tone: _Tone.warning,
        head: 'Already used',
        body:
            '$title${when != null ? '\nScanned earlier at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(when))}.' : ''}',
      );
      return;
    }
    if (reason == 'expired') {
      // A recurring ticket from a cycle that has rolled over (used up).
      final ended = parseDate(res['expiredAt']);
      await _showSheet(
        tone: _Tone.warning,
        head: 'Expired — from a cycle that has ended',
        body: ended != null
            ? '$title\nCycle ended ${fmtInstant(ended)} — they need the current one.'
            : '$title\nThey need the current cycle\'s ticket.',
      );
      return;
    }
    await _showSheet(
      tone: _Tone.error,
      head: 'Not paid',
      body: '$title\nThis ticket has not been paid for.',
    );
  }

  Future<void> _showCheckInResult(Map<String, dynamic> res) async {
    final status = res['status'] as String? ?? '';
    final title = res['eventTitle'] as String? ?? 'this event';
    switch (status) {
      case 'checked_in':
        HapticFeedback.mediumImpact();
        // Refresh whatever event screens are behind the scanner.
        ref.invalidate(eventDetailProvider);
        // What the check-in earned (gamification) — the reward moment for
        // games that never open a scoreboard.
        final reward = res['reward'] is Map
            ? Map<String, dynamic>.from(res['reward'] as Map)
            : null;
        if (reward != null && ((reward['xp'] as num?)?.toInt() ?? 0) > 0) {
          ref.invalidate(yourWeekProvider);
          ref.invalidate(myProgressionProvider);
        }
        final done = await _showSheet(
          tone: _Tone.success,
          head: "You're in",
          body: res['letInBy'] is String
              ? 'Checked in to $title. Let in by ${res['letInBy']}.'
              : 'Checked in to $title.',
          reward: reward,
          doneButton: true,
        );
        if (done && mounted) context.pop();
        return;
      case 'already_checked_in':
        ref.invalidate(eventDetailProvider);
        final done = await _showSheet(
          tone: _Tone.success,
          head: 'Already checked in',
          body: "You're already on the list for $title.",
          doneButton: true,
        );
        if (done && mounted) context.pop();
        return;
      case 'payment_required':
        await _showSheet(
          tone: _Tone.warning,
          head: 'Payment required',
          body: res['reason'] as String? ??
              'This event needs a paid ticket before check-in. Open the event page to pay, then scan again.',
        );
        return;
      case 'rsvp_required':
        // "RSVP required" event and this player holds no spot: the event
        // page is where they RSVP (if spots are left), then scan again.
        final slug = res['eventSlug'] as String?;
        final act = await _showSheet(
          tone: _Tone.warning,
          head: 'RSVP first',
          body: res['reason'] as String? ??
              'This event needs an RSVP before check-in. Open the event, RSVP, then scan again.',
          actionLabel: slug != null ? 'Open the event to RSVP' : null,
        );
        if (act && mounted && slug != null) context.push('/events/$slug');
        return;
      case 'full':
        await _showSheet(
          tone: _Tone.warning,
          head: 'This event is full',
          body: res['reason'] as String? ?? 'Every spot is taken.',
        );
        return;
      case 'limit_reached':
        await _showSheet(
          tone: _Tone.warning,
          head: 'Check-ins are full',
          body: res['reason'] as String? ??
              "This group's monthly check-in limit has been reached.",
        );
        return;
      case 'fined':
        await _showSheet(
          tone: _Tone.warning,
          head: 'Outstanding fine',
          body: res['reason'] as String? ??
              'You have an unpaid fine with this group — settle it to check in.',
        );
        return;
      case 'self_checkin':
        // An organiser scanned their own event. Explain, and when they are
        // the only admin, take them straight to where they can fix that.
        final groupId = res['groupId'] as String?;
        final others = (res['otherAdmins'] as num?)?.toInt() ?? 0;
        final act = await _showSheet(
          tone: _Tone.warning,
          head: "That's your own QR",
          body: res['reason'] as String? ??
              "Organisers can't check themselves in. Make a trusted member an admin and ask them to check you in.",
          actionLabel:
              groupId != null && others == 0 ? 'Make someone an admin' : null,
        );
        if (act && mounted && groupId != null) {
          context.push('/groups/$groupId/members');
        }
        return;
      default:
        await _showSheet(
            tone: _Tone.error, head: 'Hmm', body: 'Unexpected result: $status');
    }
  }

  /// The result sheet (web: ScanResultModal). Returns true when the primary
  /// action ("Done" or [actionLabel]) was tapped.
  Future<bool> _showSheet({
    required _Tone tone,
    required String head,
    required String body,
    bool doneButton = false,
    // A way out of a failure, in place of "Done": returns true when tapped.
    String? actionLabel,
    Map<String, dynamic>? reward,
  }) async {
    final r = await showSpSheet<bool>(
      context,
      framed: false,
      builder: (ctx) => _ResultSheet(
        tone: tone,
        head: head,
        body: body,
        doneButton: doneButton,
        actionLabel: actionLabel,
        reward: reward,
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Keep my wards warm, so a scan knows at once whether to ask
    // "Who's checking in?" (no extra round-trip per scan).
    ref.watch(myWardsProvider);
    return _scanning ? _camera(p) : _landing(p);
  }

  // ── Camera ──────────────────────────────────────────────────────────────

  Widget _camera(AppPalette p) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeScanner();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Dim everything but the aiming window.
          IgnorePointer(
            child: CustomPaint(
              painter: _Viewfinder(
                color: _handling ? p.amber : _mint,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                _GlassButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close scanner',
                  onTap: _closeScanner,
                ),
                const Expanded(
                  child: Column(children: [
                    Text('Scan event QR',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Check in, or validate a ticket',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
                _GlassButton(
                  icon: _torch
                      ? Icons.flashlight_off_rounded
                      : Icons.flashlight_on_rounded,
                  tooltip: _torch ? 'Torch off' : 'Torch on',
                  onTap: () {
                    _controller.toggleTorch();
                    setState(() => _torch = !_torch);
                  },
                ),
              ]),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 28 + MediaQuery.of(context).padding.bottom,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: const Color(0xE60E1411),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(26),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: _handling
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _mint),
                        )
                      : const Icon(Icons.qr_code_scanner_rounded,
                          size: 20, color: _mint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _handling
                        ? 'Checking the code…'
                        : 'Point at the event check-in QR — or a ticket QR to validate a holder.',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, height: 1.4),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Landing ─────────────────────────────────────────────────────────────

  Widget _landing(AppPalette p) {
    const steps = [
      'Tap Open scanner and allow camera access.',
      "Point your camera at the event's QR code displayed by the organizer.",
      "You're checked in instantly and added to the attendee list.",
    ];
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SpHeader(title: 'Scan QR', subtitle: 'Check in to an event'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // Dark call to action.
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: CustomPaint(
                    painter: _PitchLines(),
                    child: Container(
                      color: p.hero.withAlpha(0),
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(26),
                              borderRadius: BorderRadius.circular(17),
                            ),
                            child: const Icon(Icons.qr_code_scanner_rounded,
                                size: 26, color: _mint),
                          ),
                          const SizedBox(height: 16),
                          const Text('CHECK IN',
                              style: TextStyle(
                                  color: _mint,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.4)),
                          const SizedBox(height: 6),
                          Text('Check in to an event',
                              style: TextStyle(
                                  color: p.onHero,
                                  fontSize: 24,
                                  height: 1.15,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(
                            "Scan the event's QR code to check yourself in. The organizer will see you on the attendee list instantly.",
                            style: TextStyle(
                                color: p.heroMuted,
                                fontSize: 13.5,
                                height: 1.5),
                          ),
                          const SizedBox(height: 20),
                          Material(
                            color: Colors.white,
                            shape: const StadiumBorder(),
                            child: InkWell(
                              customBorder: const StadiumBorder(),
                              onTap: _openScanner,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 14),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.photo_camera_rounded,
                                          size: 19, color: Color(0xFF0E1411)),
                                      SizedBox(width: 8),
                                      Text('Open scanner',
                                          style: TextStyle(
                                              color: Color(0xFF0E1411),
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                    ]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Organisers use the same scanner at the gate.
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    SpIconTile(Icons.confirmation_num_outlined,
                        bg: p.orangeTint, fg: p.orangeInk, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Validating tickets?',
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                              "Organisers: scan a holder's ticket QR with the same scanner to let them in.",
                              style: TextStyle(
                                  color: p.muted, fontSize: 12.5, height: 1.4)),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: SpSectionTitle('How it works'),
                ),
                const SizedBox(height: 10),
                SpListCard(children: [
                  for (var i = 0; i < steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 12),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: p.accentTint, shape: BoxShape.circle),
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      color: p.greenText,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(steps[i],
                                    style: TextStyle(
                                        color: p.muted,
                                        fontSize: 13.5,
                                        height: 1.4)),
                              ),
                            ),
                          ]),
                    ),
                ]),
                // AdMob native (Android). Takes no space until it fills.
                const AdMobNativeCard(padding: EdgeInsets.only(top: 14)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Translucent round button for the camera overlay.
class _GlassButton extends StatelessWidget {
  const _GlassButton(
      {required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withAlpha(36),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Dims the camera outside a rounded square and draws its corner brackets.
class _Viewfinder extends CustomPainter {
  _Viewfinder({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width * 0.68;
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.45),
        width: side,
        height: side);
    final window = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(window),
      ),
      Paint()..color = Colors.black.withAlpha(120),
    );
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const r = 28.0;
    const len = 34.0;
    final l = rect.left, t = rect.top, rt = rect.right, b = rect.bottom;
    // Top-left, top-right, bottom-right, bottom-left brackets.
    canvas.drawPath(
        Path()
          ..moveTo(l, t + r + len)
          ..lineTo(l, t + r)
          ..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))
          ..lineTo(l + r + len, t),
        pen);
    canvas.drawPath(
        Path()
          ..moveTo(rt - r - len, t)
          ..lineTo(rt - r, t)
          ..arcToPoint(Offset(rt, t + r), radius: const Radius.circular(r))
          ..lineTo(rt, t + r + len),
        pen);
    canvas.drawPath(
        Path()
          ..moveTo(rt, b - r - len)
          ..lineTo(rt, b - r)
          ..arcToPoint(Offset(rt - r, b), radius: const Radius.circular(r))
          ..lineTo(rt - r - len, b),
        pen);
    canvas.drawPath(
        Path()
          ..moveTo(l + r + len, b)
          ..lineTo(l + r, b)
          ..arcToPoint(Offset(l, b - r), radius: const Radius.circular(r))
          ..lineTo(l, b - r - len),
        pen);
  }

  @override
  bool shouldRepaint(covariant _Viewfinder old) => old.color != color;
}

/// The dark card's background: hero colour, a green glow and pitch lines.
class _PitchLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E1411), Color(0xFF123F2A)],
        ).createShader(rect),
    );
    canvas.drawCircle(Offset(size.width * 0.95, size.height * 0.05),
        size.width * 0.45, Paint()..color = const Color(0x2617A65E));
    final line = Paint()
      ..color = const Color(0x17FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cx = size.width * 0.8;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), line);
    canvas.drawCircle(Offset(cx, size.height * 0.5), 54, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Result sheet (web: ScanResultModal).
class _ResultSheet extends StatelessWidget {
  const _ResultSheet({
    required this.tone,
    required this.head,
    required this.body,
    required this.doneButton,
    this.actionLabel,
    this.reward,
  });
  final _Tone tone;
  final String head;
  final String body;
  final bool doneButton;
  final String? actionLabel;
  final Map<String, dynamic>? reward;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (circleBg, circleFg, icon) = switch (tone) {
      _Tone.success => (p.accent, Colors.white, Icons.check_rounded),
      _Tone.warning => (p.orangeTint, p.orangeInk, Icons.priority_high_rounded),
      _Tone.error => (p.liveTint, p.danger, Icons.close_rounded),
    };
    final xp = (reward?['xp'] as num?)?.toInt() ?? 0;
    final hasPrimary = actionLabel != null || doneButton;

    Widget pillBtn(String label, IconData? i, bool ink, VoidCallback onTap) =>
        Material(
          color: ink ? p.hero : p.surface2,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: SizedBox(
              height: 50,
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (i != null) ...[
                  Icon(i, size: 18, color: ink ? p.onHero : p.ink),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: ink ? p.onHero : p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        );

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SheetScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: p.line, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Container(
              width: 68,
              height: 68,
              decoration:
                  BoxDecoration(color: circleBg, shape: BoxShape.circle),
              child: Icon(icon, size: 38, color: circleFg),
            ),
            const SizedBox(height: 14),
            Text(head,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: tone == _Tone.success ? p.greenText : p.ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 14, height: 1.45)),
            if (tone == _Tone.success && reward != null && xp > 0) ...[
              const SizedBox(height: 16),
              _RewardBlock(reward: reward!),
            ],
            const SizedBox(height: 20),
            if (actionLabel != null) ...[
              pillBtn(actionLabel!, Icons.person_add_alt_1_rounded, true,
                  () => Navigator.pop(context, true)),
              const SizedBox(height: 8),
            ],
            pillBtn('Scan another code', Icons.qr_code_scanner_rounded,
                actionLabel == null, () => Navigator.pop(context, false)),
            if (doneButton) ...[
              const SizedBox(height: 8),
              pillBtn('Done', null, false, () => Navigator.pop(context, true)),
            ] else if (!hasPrimary) ...[
              const SizedBox(height: 4),
            ],
          ]),
        ),
      ),
    );
  }
}

/// What the check-in earned: level + XP, progress, per-reason lines, streak
/// and unlocks, in one green block.
class _RewardBlock extends StatelessWidget {
  const _RewardBlock({required this.reward});
  final Map<String, dynamic> reward;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final xp = (reward['xp'] as num?)?.toInt() ?? 0;
    final level = reward['level'];
    final title = reward['title'] as String? ?? '';
    final progress =
        ((reward['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
    final streak = (reward['weeklyStreak'] as num?)?.toInt() ?? 0;
    final lines = reward['lines'] is List ? reward['lines'] as List : const [];
    final unlocked =
        reward['unlocked'] is List ? reward['unlocked'] as List : const [];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.accentTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Lv $level${title.isNotEmpty ? ' · $title' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          Text('+$xp XP',
              style: TextStyle(
                  color: p.greenText,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: p.surface,
            color: p.accent,
          ),
        ),
        for (final l in lines)
          if (l is Map && l['label'] is String)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(
                  child: Text(l['label'] as String,
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ),
                Text('+${(l['xp'] as num?)?.toInt() ?? 0}',
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
            ),
        if (streak > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.local_fire_department_rounded,
                  size: 15, color: p.orangeInk),
              const SizedBox(width: 5),
              Text('$streak-week streak',
                  style: TextStyle(
                      color: p.orangeInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        for (final u in unlocked)
          if (u is Map && u['title'] is String)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(Icons.auto_awesome_rounded, size: 15, color: p.greenText),
                const SizedBox(width: 5),
                Expanded(
                  child: Text('Achievement unlocked: ${u['title']}',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
      ]),
    );
  }
}
