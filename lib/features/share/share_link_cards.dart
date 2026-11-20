import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/share/share_paths.dart';
import 'package:sportpadi_mobile/data/share/share_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/inbox/announcement_card.dart'
    show openAnnouncementUrl;
import 'package:sportpadi_mobile/features/share/share_sheet.dart';

/// A SportPadi link in a message gets a card under the bubble
/// (docs/wiki/sharing.md): the item as the READER may see it — a private
/// event, a ward kept private, a highlight they can't see come back
/// unavailable and show the muted "This content isn't available" card.
/// Cards go through [SharePreviewCache]: every card a screen builds is one
/// preview-many request, kept 5 minutes per (reader, link). Tap opens the
/// item through the app's link resolver (`openAnnouncementUrl` →
/// `handleDeepLink`), or the browser when the app has no screen for it.
class ShareLinkCards extends ConsumerWidget {
  const ShareLinkCards({super.key, required this.body});
  final String body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    // Wait for a KNOWN session (app review LOW-2): asked while it is loading
    // or "unknown" (a slow get-session), the card would go as nobody while
    // the request still carries the token — and the server answers such a
    // mismatch "unavailable".
    if (!session.hasValue || session.valueOrNull?.isUnknown == true) {
      return const SizedBox.shrink();
    }
    final viewer = session.valueOrNull?.user?.id;
    final urls = shareUrlsIn(body, ref.watch(appConfigProvider).apiBaseUrl);
    if (urls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final u in urls)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _OneCard(url: u, viewer: viewer),
          ),
      ],
    );
  }
}

class _OneCard extends ConsumerWidget {
  const _OneCard({required this.url, required this.viewer});
  final String url;
  final String? viewer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final pk = (viewer: viewer, url: url);
    final pv = ref.watch(sharePreviewProvider(pk));
    if (pv.isLoading && !pv.hasValue) {
      return Container(
        height: 78,
        decoration: BoxDecoration(
            color: p.surface2, borderRadius: BorderRadius.circular(20)),
      );
    }
    if (pv.hasError) {
      // The request failed: that says nothing about the item (review L1) —
      // a neutral card that asks again on a tap, never "removed or private".
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => ref.invalidate(sharePreviewProvider(pk)),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: p.surface2, borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: p.surface, borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.refresh_rounded, size: 18, color: p.muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.share_couldntLoadPreview,
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text(l.share_tryAgain,
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );
    }
    final got = pv.valueOrNull;
    final card = got != null && got.available ? got : null;
    if (card == null) {
      // The server's answer: not one this reader may see (or gone).
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: p.surface2, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: p.surface, borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.lock_outline_rounded, size: 18, color: p.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.share_notAvailable,
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                Text(l.share_notAvailableHint,
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ],
            ),
          ),
        ]),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => unawaited(openAnnouncementUrl(ref, card.url!)),
        child: SharePreviewCard(
          kind: card.kind,
          title: card.title!,
          subtitle: card.subtitle,
          imageUrl: card.imageUrl,
        ),
      ),
    );
  }
}
