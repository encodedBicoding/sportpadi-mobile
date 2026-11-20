import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Visitors (owner, 2026-11-19 — workspace `docs/wiki/highlights.md`,
/// "Visitors"): someone with no account watches public players' highlights —
/// the guest dock's Highlights tab (Discover only), a shared post, a match
/// reel, the comments read-only — and is asked to sign up for everything
/// else. The server decides WHAT they see (public adults' posts only, its
/// visitor rule); this file is what the app asks them, and where it brings
/// them back to. Web twin: `components/highlights/SignUpPrompt.tsx`.

/// What a visitor tried to do.
enum HighlightVisitorAction { like, comment, follow, report, post }

/// Is the person looking a signed-out VISITOR? Only when the server said so
/// (no token, a hard 401, no user): a session that could not be CHECKED
/// (`SessionState.isUnknown` — a timed-out request) still carries its token,
/// so its requests are a member's and it is never asked to sign up.
final highlightVisitorProvider = Provider<bool>((ref) {
  final s = ref.watch(authControllerProvider).valueOrNull;
  return s != null && !s.isAuthenticated && !s.isUnknown;
});

/// Where a visitor who signs up from [postId] comes back to: the post's own
/// page, the reel's address when they were in one ([reel] = its query), and
/// with the comments open again after "comment".
String highlightVisitorReturnTo(String postId,
    {Map<String, String>? reel, bool comments = false}) {
  final q = <String, String>{...?reel, if (comments) 'comments': '1'};
  return Uri(path: '/highlights/$postId', queryParameters: q.isEmpty ? null : q)
      .toString();
}

/// The sign-in page — in sign-up mode when [signUp] — coming back to
/// [returnTo] afterwards (`SignInScreen._leaveAfterSuccess`; the router
/// keeps only an in-app path, `safeRedirectTarget`).
String highlightSignInHref(String returnTo, {bool signUp = false}) => Uri(
      path: '/sign-in',
      queryParameters: {if (signUp) 'mode': 'signup', 'redirect': returnTo},
    ).toString();

/// The one sheet a visitor gets for any action: a line saying what an
/// account lets them do, "Sign up" and "Sign in". Both come back to
/// [returnTo]. [name] is the player, for "follow".
Future<void> showHighlightSignUpPrompt(
  BuildContext context, {
  required HighlightVisitorAction action,
  required String returnTo,
  String? name,
}) {
  final router = GoRouter.of(context);
  return showSpSheet<void>(
    context,
    builder: (ctx) {
      final l = ctx.l10n;
      final p = ctx.palette;
      final text = switch (action) {
        HighlightVisitorAction.like => l.highlights_visitorLikeText,
        HighlightVisitorAction.comment => l.highlights_visitorCommentText,
        HighlightVisitorAction.follow => l.highlights_visitorFollowText(name ?? ''),
        HighlightVisitorAction.report => l.highlights_visitorReportText,
        HighlightVisitorAction.post => l.highlights_visitorPostText,
      };
      void open(bool signUp) {
        Navigator.of(ctx).pop();
        // ignore: discarded_futures
        router.push(highlightSignInHref(returnTo, signUp: signUp));
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(
            title: l.highlights_visitorTitle,
            subtitle: text,
            icon: Icons.person_add_alt_1_rounded,
          ),
          const SizedBox(height: 18),
          SpButton(
            label: l.highlights_visitorSignUp,
            icon: Icons.person_add_alt_1_rounded,
            expand: true,
            onTap: () => open(true),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => open(false),
            style: TextButton.styleFrom(
              foregroundColor: p.ink,
              minimumSize: const Size(0, 48),
            ),
            child: Text(l.highlights_visitorSignIn,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
        ],
      );
    },
  );
}
