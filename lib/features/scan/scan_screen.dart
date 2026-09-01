import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';


/// Scan an event's check-in QR — the mobile version of the web /scan page.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handling = false;
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
      final res = await ref.read(eventsRepositoryProvider).checkInByQr(raw);
      if (!mounted) return;
      await _showResult(res);
    } catch (e) {
      if (mounted) await _showError('$e');
    }
    if (!mounted) return;
    setState(() => _handling = false);
    _lastCode = null;
    await _controller.start();
  }

  Future<void> _showResult(Map<String, dynamic> res) async {
    final status = res['status'] as String? ?? '';
    final title = res['eventTitle'] as String? ?? 'this event';
    String head;
    String body;
    bool success = false;
    switch (status) {
      case 'checked_in':
        head = "You're in ✅";
        body = 'Checked in to $title.';
        success = true;
        break;
      case 'already_checked_in':
        head = 'Already checked in';
        body = "You're already on the list for $title.";
        success = true;
        break;
      case 'payment_required':
        head = 'Payment required';
        body = res['reason'] as String? ??
            'This event needs a paid ticket before check-in. Open the event page to pay, then scan again.';
        break;
      case 'limit_reached':
        head = 'Check-ins are full';
        body = res['reason'] as String? ??
            "This group's monthly check-in limit has been reached.";
        break;
      case 'fined':
        head = 'Outstanding fine';
        body = res['reason'] as String? ??
            'You have an unpaid fine with this group — settle it to check in.';
        break;
      default:
        head = 'Hmm';
        body = 'Unexpected result: $status';
    }
    final goToEvent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(head),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Scan again')),
          if (success)
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Done')),
        ],
      ),
    );
    if (success && goToEvent == true && mounted) {
      context.pop();
    }
  }

  Future<void> _showError(String msg) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check-in failed'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Try again')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan to check in',
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
                const Text(
                  "Point the camera at the event's check-in QR.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
