import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'package:sportpadi_mobile/core/env/walkthrough_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/onboarding/intent_cards.dart'
    show intentTint;
import 'package:sportpadi_mobile/features/onboarding/intents.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The walkthrough that plays when someone taps a door on the welcome
/// screen: a silent 9:16 clip of the journey they're about to start, with
/// Skip and Continue both leading on (sign-in / up for a visitor, the start
/// wizard for a member). Swiping the sheet away just closes it.
/// Web twin: components/intents/IntentVideoModal.tsx.
Future<void> showIntentWalkthrough(
  BuildContext context, {
  required UserIntent intent,
  required String proceedLabel,
  required VoidCallback onProceed,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _IntentVideoSheet(
      intent: intent,
      proceedLabel: proceedLabel,
      onProceed: () {
        Navigator.of(ctx).pop();
        onProceed();
      },
    ),
  );
}

class _IntentVideoSheet extends ConsumerStatefulWidget {
  const _IntentVideoSheet({
    required this.intent,
    required this.proceedLabel,
    required this.onProceed,
  });
  final UserIntent intent;
  final String proceedLabel;
  final VoidCallback onProceed;

  @override
  ConsumerState<_IntentVideoSheet> createState() => _IntentVideoSheetState();
}

class _IntentVideoSheetState extends ConsumerState<_IntentVideoSheet> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;
  bool _ended = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    final url =
        Uri.parse('${WalkthroughConfig.base}/${widget.intent.videoFile}');
    final c = VideoPlayerController.networkUrl(url);
    _ctrl = c;
    // ignore: discarded_futures
    c.initialize().then((_) async {
      if (!mounted) return;
      await c.setVolume(0); // the clips have no audio track anyway
      c.addListener(_onTick);
      setState(() => _ready = true);
      await c.play();
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _onTick() {
    final c = _ctrl;
    if (c == null) return;
    final v = c.value;
    final ended = v.isInitialized &&
        !v.isPlaying &&
        v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 200);
    // Repaint only when the play / pause / ended state changes — the
    // controller notifies on every position tick.
    if ((ended != _ended || v.isPlaying != _playing) && mounted) {
      setState(() {
        _ended = ended;
        _playing = v.isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final c = _ctrl;
    if (c == null || !_ready) return;
    if (_ended) {
      await c.seekTo(Duration.zero);
      await c.play();
    } else if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final i = widget.intent;
    final (bg, fg) = intentTint(p, i.key);
    final playing = _playing;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
                color: p.line, borderRadius: BorderRadius.circular(999))),
        const SizedBox(height: 12),
        Row(children: [
          SpIconTile(i.icon, bg: bg, fg: fg, size: 40, iconSize: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2)),
                  Text("Here's how it works · about a minute, no sound",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: p.muted),
            style: IconButton.styleFrom(backgroundColor: p.surface2),
          ),
        ]),
        const SizedBox(height: 12),
        // The clip: as tall as the sheet allows, 9:16, centred.
        Flexible(
          child: Center(
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: GestureDetector(
                  onTap: _toggle,
                  child: Container(
                    color: p.surface2,
                    child: Stack(fit: StackFit.expand, children: [
                      if (_ready && _ctrl != null)
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _ctrl!.value.size.width,
                            height: _ctrl!.value.size.height,
                            child: VideoPlayer(_ctrl!),
                          ),
                        )
                      else if (_failed)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                                "Couldn't load the video — carry on below.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: p.muted, fontSize: 13)),
                          ),
                        )
                      else
                        const Center(
                            child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5))),
                      if (_ready && !playing)
                        Container(
                          color: p.ink.withAlpha(60),
                          alignment: Alignment.center,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                                color: p.bg,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withAlpha(60),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6)),
                                ]),
                            child: Icon(
                                _ended
                                    ? Icons.replay_rounded
                                    : Icons.play_arrow_rounded,
                                color: p.ink,
                                size: 34),
                          ),
                        ),
                      if (_ready && playing)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                                color: p.bg.withAlpha(220),
                                shape: BoxShape.circle),
                            child: Icon(Icons.pause_rounded,
                                color: p.ink, size: 20),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          TextButton(
              onPressed: widget.onProceed,
              child: Text('Skip',
                  style: TextStyle(
                      color: p.muted, fontWeight: FontWeight.w700))),
          const Spacer(),
          SpButton(
            label: widget.proceedLabel,
            icon: Icons.arrow_forward_rounded,
            tone: SpButtonTone.brand,
            onTap: widget.onProceed,
          ),
        ]),
      ]),
    );
  }
}
