import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// Added time, any amount (web twin: StoppagePad in OfficiateClient.tsx).
///
/// One tap for the usual (+1' +2' +3' +5'); "More" opens a big stepper —
/// hold − / + to run, tap +5 / +10 / +15, or type it — for anything up to
/// 120'. "Correct" sets the period's total exactly, back to 0 if need be.
///
/// [dark] is officiant mode's black screen; otherwise it follows the app
/// palette (the game page's stoppage sheet). [startExpanded] opens straight
/// on the stepper (the sheet).
const kMaxStoppage = 120;

class StoppagePad extends StatefulWidget {
  const StoppagePad({
    super.key,
    required this.current,
    required this.onAdd,
    required this.onSet,
    this.presets = const [1, 2, 3, 5],
    this.busy = false,
    this.dark = true,
    this.startExpanded = false,
  });

  /// Stoppage already added this period.
  final int current;
  final List<int> presets;
  final bool busy;
  final bool dark;
  final bool startExpanded;
  final void Function(int minutes) onAdd;
  final void Function(int minutes) onSet;

  @override
  State<StoppagePad> createState() => _StoppagePadState();
}

enum _Mode { add, set }

class _StoppagePadState extends State<StoppagePad> {
  _Mode? _mode;
  int _n = 1;
  final _ctrl = TextEditingController(text: '1');
  Timer? _delay;
  Timer? _repeat;

  static const _amber = Color(0xFFFBBF24);

  @override
  void initState() {
    super.initState();
    if (widget.startExpanded) {
      _mode = _Mode.add;
      _n = 5;
      _ctrl.text = '5';
    }
  }

  @override
  void dispose() {
    _stop();
    _ctrl.dispose();
    super.dispose();
  }

  int get _min => _mode == _Mode.set ? 0 : 1;
  int _clamp(int v) => v < _min ? _min : (v > kMaxStoppage ? kMaxStoppage : v);

  void _setN(int v) {
    final c = _clamp(v);
    if (c == _n && _ctrl.text == '$c') return;
    setState(() => _n = c);
    _ctrl.value = TextEditingValue(
        text: '$c', selection: TextSelection.collapsed(offset: '$c'.length));
  }

  void _open(_Mode m, int start) {
    _mode = m;
    _n = _clamp(start);
    _ctrl.text = '$_n';
    if (mounted) setState(() {});
  }

  void _close() {
    _stop();
    FocusScope.of(context).unfocus();
    setState(() => _mode = null);
  }

  void _stop() {
    _delay?.cancel();
    _repeat?.cancel();
    _delay = null;
    _repeat = null;
  }

  // Tap steps once; hold keeps stepping.
  void _press(int d) {
    HapticFeedback.selectionClick();
    _setN(_n + d);
    _stop();
    _delay = Timer(const Duration(milliseconds: 380), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 70), (_) => _setN(_n + d));
    });
  }

  void _confirm() {
    final n = _clamp(_n);
    if (_mode == _Mode.add) {
      widget.onAdd(n);
    } else {
      widget.onSet(n);
    }
    if (widget.startExpanded) return; // the sheet closes itself
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = widget.dark;
    final dim = dark ? const Color(0x99FFFFFF) : p.muted;
    final faint = dark ? const Color(0x1AFFFFFF) : p.surface2;
    final ink = dark ? Colors.white : p.ink;
    final accent = dark ? _amber : p.orangeInk;
    final accentBg = dark ? const Color(0x26FBBF24) : p.orangeTint;

    Widget pill(String label, VoidCallback? onTap,
            {Color? bg, Color? fg, double h = 56, double size = 18}) =>
        Opacity(
          opacity: onTap == null ? 0.55 : 1,
          child: Material(
            color: bg ?? faint,
            borderRadius: BorderRadius.circular(h / 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(h / 2),
              onTap: onTap,
              child: SizedBox(
                height: h,
                child: Center(
                  child: Text(label,
                      style: TextStyle(
                          color: fg ?? ink, fontSize: size, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        );

    Widget stepper(String label, int d) => GestureDetector(
          onTapDown: (_) => _press(d),
          onTapUp: (_) => _stop(),
          onTapCancel: _stop,
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: faint, shape: BoxShape.circle),
            child: Text(label,
                style: TextStyle(color: ink, fontSize: 30, fontWeight: FontWeight.w800)),
          ),
        );

    final header = Row(children: [
      Expanded(
        child: Text(_mode == _Mode.set ? 'CORRECT STOPPAGE' : 'ADD STOPPAGE',
            style: TextStyle(
                color: dim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
      ),
      if (widget.current > 0 && _mode == null)
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _open(_Mode.set, widget.current),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: faint, borderRadius: BorderRadius.circular(999)),
            child: Text("+${widget.current}' added · Correct",
                style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ),
    ]);

    if (_mode == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const SizedBox(height: 6),
        Row(children: [
          for (final m in widget.presets.take(4)) ...[
            Expanded(
              child: pill("+$m'", widget.busy ? null : () => widget.onAdd(m),
                  bg: accentBg, fg: accent),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: pill('More', widget.busy ? null : () => _open(_Mode.add, 10), size: 14),
          ),
        ]),
      ]);
    }

    final n = _clamp(_n);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: dark ? const Color(0x12FFFFFF) : p.surface,
          borderRadius: BorderRadius.circular(26),
          border: dark ? null : Border.all(color: p.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            stepper('−', -1),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (_mode == _Mode.add)
                    Text('+',
                        style: TextStyle(color: accent, fontSize: 26, fontWeight: FontWeight.w800)),
                  IntrinsicWidth(
                    child: TextField(
                      controller: _ctrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      textAlign: TextAlign.center,
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        setState(() => _n = parsed == null ? _min : _clamp(parsed));
                      },
                      onSubmitted: (_) => _setN(_n),
                      style: TextStyle(
                        color: accent,
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  Text("'",
                      style: TextStyle(color: accent, fontSize: 26, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            stepper('+', 1),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final d in const [5, 10, 15]) ...[
              if (d != 5) const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _setN(_n + d),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration:
                      BoxDecoration(color: faint, borderRadius: BorderRadius.circular(999)),
                  child: Text('+$d',
                      style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          Row(children: [
            if (!widget.startExpanded || _mode == _Mode.set) ...[
              Expanded(
                child: pill('Cancel', widget.startExpanded ? () => setState(() => _mode = _Mode.add) : _close,
                    size: 14),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              flex: 2,
              child: pill(
                _mode == _Mode.add
                    ? "Add +$n'"
                    : n == 0
                        ? 'Clear stoppage'
                        : "Set to +$n'",
                widget.busy || (_mode == _Mode.add && n < 1) ? null : _confirm,
                bg: dark ? _amber : p.hero,
                fg: dark ? const Color(0xFF0E1411) : p.onHero,
                size: 16,
              ),
            ),
          ]),
          if (widget.startExpanded && widget.current > 0 && _mode == _Mode.add) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => _open(_Mode.set, widget.current),
                child: Text("+${widget.current}' added so far · Correct the total",
                    style: TextStyle(color: dim, fontSize: 12)),
              ),
            ),
          ],
          if (_mode == _Mode.set) ...[
            const SizedBox(height: 6),
            Text(
              "Sets this period's added time to exactly this — it replaces the +${widget.current}' so far.",
              textAlign: TextAlign.center,
              style: TextStyle(color: dim, fontSize: 11),
            ),
          ],
        ]),
      ),
    ]);
  }
}
