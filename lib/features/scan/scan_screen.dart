import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/tickets/tickets_repository.dart';

/// One scanner for both QR kinds:
///  - event check-in QRs (a player checks themselves in), and
///  - ticket QRs (TKT-…): an organizer validates a holder at the gate.
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
  String? _lastCode;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
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
        // An event's check-in QR — self check-in (player flow).
        final res = await ref.read(eventsRepositoryProvider).checkInByQr(raw);
        if (!mounted) return;
        await _showCheckInResult(res);
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
    await _controller.start();
  }

  Future<void> _showRedeemResult(Map<String, dynamic> res) async {
    final ok = res['ok'] == true;
    final title = res['ticketTitle'] as String? ?? 'Ticket';
    if (ok) {
      HapticFeedback.mediumImpact();
      await _showSheet(
        tone: _Tone.success,
        head: 'Valid — checked in',
        body: '$title\nThe holder is in. 🎟',
      );
      return;
    }
    final reason = res['reason'] as String? ?? '';
    if (reason == 'already') {
      final at = res['redeemedAt'] as String?;
      final when =
          at != null ? DateTime.tryParse(at)?.toLocal() : null;
      await _showSheet(
        tone: _Tone.warning,
        head: 'Already used',
        body:
            '$title${when != null ? '\nScanned earlier at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(when))}.' : ''}',
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
        final done = await _showSheet(
          tone: _Tone.success,
          head: "You're in ✅",
          body: 'Checked in to $title.',
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
      default:
        await _showSheet(
            tone: _Tone.error, head: 'Hmm', body: 'Unexpected result: $status');
    }
  }

  /// Solid, high-contrast result sheet — readable over the camera feed.
  /// Returns true when "Done" was tapped (only shown with [doneButton]).
  Future<bool> _showSheet({
    required _Tone tone,
    required String head,
    required String body,
    bool doneButton = false,
  }) async {
    final p = context.palette;
    final color = switch (tone) {
      _Tone.success => p.accent,
      _Tone.warning => p.amber,
      _Tone.error => p.danger,
    };
    final icon = switch (tone) {
      _Tone.success => Icons.check_circle_rounded,
      _Tone.warning => Icons.error_rounded,
      _Tone.error => Icons.cancel_rounded,
    };
    final r = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: p.surface,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: color.withAlpha(31),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 42, color: color),
              ),
              const SizedBox(height: 14),
              Text(head,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p.muted, fontSize: 14, height: 1.45)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, false),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Scan again'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.ink,
                      side: BorderSide(color: p.line),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (doneButton) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (!_scanning) return _landing(p);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            _controller.stop();
            setState(() => _scanning = false);
          },
        ),
        title: const Text('Scan QR',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Aiming frame.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(
                    color: _handling ? p.amber : p.accent, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Column(children: [
              if (_handling)
                const CircularProgressIndicator(strokeWidth: 2)
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(153),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "Point at an event check-in QR — or a ticket QR to validate a holder.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  /// Landing page (mirrors web /scan): what scanning does + how it works,
  /// with the camera one tap away.
  Widget _landing(AppPalette p) {
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Scan QR code',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.line),
            ),
            child: Column(children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: p.accent.withAlpha(26),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.qr_code_2_rounded, size: 44, color: p.accent),
              ),
              const SizedBox(height: 16),
              Text('CHECK IN TO AN EVENT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Text(
                "Scan the event's QR code to check yourself in — the organizer sees you on the attendee list instantly. Organizers: scan a holder's ticket QR to validate it at the gate.",
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() => _scanning = true);
                    // Restart after a previous stop; harmless if fresh.
                    _controller.start().catchError((_) {});
                  },
                  icon: const Icon(Icons.photo_camera_rounded, size: 19),
                  label: const Text('Open QR scanner'),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.qr_code_scanner_rounded, size: 19, color: p.accent),
                const SizedBox(width: 8),
                Text('HOW IT WORKS',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
              ]),
              const SizedBox(height: 12),
              _step(p, 'Tap Open QR scanner above and allow camera access.'),
              _step(p,
                  "Point your camera at the event's QR code displayed by the organizer."),
              _step(p,
                  "You'll be checked in instantly and added to the attendee list."),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _step(AppPalette p, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.check_circle_rounded, size: 18, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
          ),
        ]),
      );
}
