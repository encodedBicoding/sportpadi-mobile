/// Turning a sportpadi.com URL into somewhere in the app.
///
/// One resolver, two callers: a tapped push notification (whose payload carries
/// a web path) and a Universal Link / App Link opened from outside the app.
/// Keeping them on the same function is the point — every time these drifted
/// apart, one of them started dropping people on the wrong screen.
///
/// Three kinds of answer, because the app has three kinds of destination:
///   • `route`  — a pushable go_router path.
///   • `tab`    — a bottom-tab index, for the handful of URLs whose home is a
///                tab rather than a page (Browse, Groups, My tournaments…).
///   • `web`    — this URL must be handed BACK to a browser. Android App Links
///                can't express path exclusions, so the OS will hand us
///                /groups/x/wallet/activate whether we want it or not; the
///                handler re-opens those externally instead of swallowing them.
/// All three empty means "no native equivalent" — the caller decides whether
/// that's the Home screen (a deep link) or the notification inbox (a push).
library;

/// Bottom-tab indices, as HomeShell switches on them.
class HomeTab {
  static const home = 0;
  static const browse = 1;
  static const groups = 2;
  static const tournaments = 3;
  static const profile = 4;
}

typedef LinkTarget = ({String? route, int? tab, bool web});

const LinkTarget _none = (route: null, tab: null, web: false);
const LinkTarget _web = (route: null, tab: null, web: true);
LinkTarget _route(String r) => (route: r, tab: null, web: false);
LinkTarget _tab(int t) => (route: null, tab: t, web: false);

/// Paths that must NEVER be taken over by the app.
///
/// A hosted checkout, an OAuth redirect or a Stripe onboarding step has to
/// finish in a real browser; opening it in a WebView-less app means the user
/// stares at a dead end and, in the payment case, loses the transaction. The
/// AASA and the Android intent-filters exclude these too — this is the
/// belt-and-braces copy, for a link that reaches us some other way (a push
/// payload, a pasted URL).
bool _mustStayOnWeb(String path) {
  if (path.startsWith('/t/')) return true; // hosted ticket payment
  if (path.startsWith('/api/')) return true;
  if (path.startsWith('/auth')) return true;
  if (path.startsWith('/reset')) return true;
  if (path.startsWith('/forgot')) return true;
  if (path.startsWith('/verify-email')) return true;
  if (path.startsWith('/.well-known/')) return true;
  // Group pages that exist ONLY on the web, and must not be swallowed:
  //
  //   wallet/activate  Stripe Connect onboarding, a hosted web flow.
  //   upgrade, billing plan purchase and invoices. On Android these are the
  //                    ONLY way to upgrade — there's no Play Billing yet — and
  //                    they're exactly what the plan-nudge email links to. An
  //                    app that ate that link would kill the upgrade path.
  if (RegExp(r'^/groups/[^/]+/(wallet/activate|upgrade|billing)')
      .hasMatch(path)) {
    return true;
  }
  return false;
}

/// Resolve a full URL, or a bare path, to somewhere in the app.
LinkTarget resolveLink(String? url) {
  if (url == null || url.trim().isEmpty) return _none;
  final raw = url.trim();

  final uri = Uri.tryParse(raw);
  final path = (raw.startsWith('http') ? uri?.path : null) ?? _pathOf(raw);
  if (path.isEmpty) return _none;
  final query = uri?.queryParameters ?? const <String, String>{};

  if (_mustStayOnWeb(path)) return _web;

  RegExpMatch? m;

  // ── Tournaments inside a group ────────────────────────────────────────────
  // Squad pages carry ?respond= from a call-up, and the web page addresses its
  // formation editor with ?tab=formation where the app has a real route.
  m = RegExp(r'^/groups/([^/]+)/tournaments/([^/]+)/teams/([^/]+)/formation/?$')
      .firstMatch(path);
  if (m != null) {
    return _route(
        '/groups/${m[1]}/tournaments/${m[2]}/teams/${m[3]}/formation');
  }
  m = RegExp(r'^/groups/([^/]+)/tournaments/([^/]+)/teams/([^/]+)/?$')
      .firstMatch(path);
  if (m != null) {
    final base = '/groups/${m[1]}/tournaments/${m[2]}/teams/${m[3]}';
    if (query['tab'] == 'formation') return _route('$base/formation');
    return _route(query.containsKey('respond') ? '$base?respond=1' : base);
  }
  // The team LIST has no native screen — the tournament itself is the nearest
  // honest destination.
  m = RegExp(r'^/groups/([^/]+)/tournaments/([^/]+)/teams/?$').firstMatch(path);
  if (m != null) return _route('/groups/${m[1]}/tournaments/${m[2]}');

  m = RegExp(r'^/groups/([^/]+)/tournaments/([^/]+)/?$').firstMatch(path);
  if (m != null) return _route('/groups/${m[1]}/tournaments/${m[2]}');

  // ── Group money + admin pages ─────────────────────────────────────────────
  m = RegExp(r'^/groups/([^/]+)/wallet/(approvals|withdrawals)').firstMatch(path);
  if (m != null) return _route('/groups/${m[1]}/wallet/withdrawals');
  m = RegExp(r'^/groups/([^/]+)/wallet').firstMatch(path);
  if (m != null) return _route('/groups/${m[1]}/wallet');

  // Everything the app has a dedicated group sub-screen for, one to one.
  m = RegExp(
    r'^/groups/([^/]+)/(tickets|leaderboard|members|followers|events|outstanding|invites|plan|fines)/?$',
  ).firstMatch(path);
  if (m != null) return _route('/groups/${m[1]}/${m[2]}');

  // Anything else group-scoped (billing, upgrade, edit…) → the group.
  m = RegExp(r'^/groups/([^/]+)').firstMatch(path);
  if (m != null) return _route('/groups/${m[1]}');

  // ── Players ───────────────────────────────────────────────────────────────
  m = RegExp(r'^/players/([^/]+)/groups/([^/]+)/?$').firstMatch(path);
  if (m != null) return _route('/players/${m[1]}/groups/${m[2]}');
  m = RegExp(r'^/players/([^/]+)/tournaments/([^/]+)/?$').firstMatch(path);
  if (m != null) return _route('/players/${m[1]}/tournaments/${m[2]}');
  m = RegExp(r'^/players/([^/]+)/events/([^/]+)/?$').firstMatch(path);
  if (m != null) return _route('/players/${m[1]}/events/${m[2]}');
  m = RegExp(r'^/players/([^/]+)/?$').firstMatch(path);
  if (m != null) {
    // ?sport= addresses a category on the web page; the app keeps its own
    // picker state, so the id is enough.
    return _route('/players/${m[1]}');
  }

  // ── Teams ─────────────────────────────────────────────────────────────────
  m = RegExp(r'^/teams/([^/]+)/(formation|manage)/?$').firstMatch(path);
  if (m != null) return _route('/teams/${m[1]}/${m[2]}');
  m = RegExp(r'^/teams/([^/]+)/?$').firstMatch(path);
  if (m != null) return _route('/teams/${m[1]}');
  m = RegExp(r'^/join-team/([^/]+)').firstMatch(path);
  if (m != null) return _route('/join-team/${m[1]}');

  // ── Events, games, invites ────────────────────────────────────────────────
  m = RegExp(r'^/events/([^/]+)').firstMatch(path);
  if (m != null) return _route('/events/${m[1]}');
  // The live scoresheet — the most shared screen in the app, and the one this
  // resolver used to miss entirely.
  m = RegExp(r'^/games/([^/]+)/summary/?$').firstMatch(path);
  if (m != null) return _route('/games/${m[1]}/summary');
  m = RegExp(r'^/games/([^/]+)/officiate/?$').firstMatch(path);
  if (m != null) return _route('/games/${m[1]}/officiate');
  m = RegExp(r'^/games/([^/]+)').firstMatch(path);
  if (m != null) return _route('/games/${m[1]}');
  m = RegExp(r'^/join/([^/]+)').firstMatch(path);
  if (m != null) return _route('/join/${m[1]}');

  // ── Tournaments (top level) ───────────────────────────────────────────────
  if (RegExp(r'^/tournaments/invitations/?$').hasMatch(path)) {
    return _route('/tournaments/invitations');
  }
  m = RegExp(r'^/tournaments/teams/([^/]+)/?$').firstMatch(path);
  if (m != null) return _route('/tournaments/teams/${m[1]}');
  m = RegExp(r'^/tournaments/([^/]+)/?$').firstMatch(path);
  if (m != null) return _route('/tournaments/${m[1]}');
  if (RegExp(r'^/tournaments/?$').hasMatch(path)) {
    return _tab(HomeTab.tournaments);
  }

  // ── The player's own pages ────────────────────────────────────────────────
  if (path.startsWith('/tickets')) return _route('/tickets');
  if (path.startsWith('/fines')) return _route('/fines');
  if (path.startsWith('/my-qr')) return _route('/my-qr');
  if (path.startsWith('/notifications')) return _route('/notifications');
  if (path.startsWith('/scan')) return _route('/scan');
  if (path.startsWith('/settings')) return _route('/settings');
  if (path.startsWith('/leaderboards')) return _route('/leaderboards');
  // Profile anchors that name the progress block open the full progress page.
  if (path.startsWith('/profile') && (uri?.fragment ?? '') == 'achievements') {
    return _route('/progress');
  }

  // ── URLs whose home is a tab, not a page ──────────────────────────────────
  if (path.startsWith('/profile')) return _tab(HomeTab.profile);
  if (path.startsWith('/discover') || path.startsWith('/browse')) {
    return _tab(HomeTab.browse);
  }
  if (RegExp(r'^/groups/?$').hasMatch(path)) return _tab(HomeTab.groups);
  if (path == '/' || path.startsWith('/dashboard') || path.startsWith('/home')) {
    return _tab(HomeTab.home);
  }

  // Marketing pages and anything unknown: no native equivalent. The caller
  // decides where that lands.
  return _none;
}

/// A bare path, tolerating one that arrived without its leading slash.
String _pathOf(String raw) {
  final q = raw.indexOf('?');
  final justPath = q >= 0 ? raw.substring(0, q) : raw;
  if (justPath.isEmpty) return '';
  return justPath.startsWith('/') ? justPath : '/$justPath';
}

/// Back-compatible helper for callers that only want a route.
String? resolveLinkRoute(String? url) => resolveLink(url).route;
