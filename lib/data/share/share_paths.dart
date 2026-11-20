/// Sharing — which links in a message are SportPadi items: the app's copy of
/// the server's path table (`packages/lib/src/sharePaths.ts` in the
/// workspace; docs/wiki/sharing.md). Only decides whether a chat bubble asks
/// for a card — the SERVER still decides what the card is, and an item the
/// reader may not see comes back unavailable. Pure Dart.
library;

const _uuid =
    '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
const _slug = '[A-Za-z0-9][A-Za-z0-9_-]{0,159}';
// A secret invite code (packages/lib/src/inviteLinks.ts): 22 base62.
const _code = '[A-Za-z0-9]{22}';
const _locales = {'pcm', 'yo', 'ig', 'ha', 'fr', 'es', 'pt', 'ar', 'de', 'hi'};

final List<RegExp> _table = [
  for (final src in [
    '/e/$_slug',
    '/events/$_slug',
    '/share/event/$_slug',
    '/groups/$_uuid',
    '/g/$_slug',
    '/share/group/$_slug',
    '/join/$_code',
    '/join/$_uuid',
    '/groups/$_uuid/tournaments/$_uuid',
    '/leagues/(?!mine/?\$)$_slug',
    '/groups/$_uuid/leagues/$_uuid',
    '/competitions/$_slug',
    '/highlights/$_uuid',
    '/t/$_uuid',
    '/join-team/$_code',
    '/join-team/$_uuid',
    '/register/[A-Za-z0-9]{8,40}',
    '/players/$_uuid',
    '/games/$_uuid(?:/summary)?',
    '/groups/$_uuid/teams/$_uuid',
    '/teams/$_uuid',
    '/tournaments/teams/$_uuid',
  ])
    RegExp('^$src/?\$'),
];

/// Is [path] one of the item paths (a leading language prefix dropped)?
bool isSharePath(String path) {
  var p = path;
  final seg = p.split('/').length > 1 ? p.split('/')[1] : '';
  if (_locales.contains(seg)) p = p.substring(seg.length + 1);
  if (p.isEmpty) p = '/';
  return _table.any((r) => r.hasMatch(p));
}

/// Is [url] one of ours: on [baseUrl]'s host or sportpadi.com (with or
/// without www), or the app's own `sportpadi://sportpadi.com/…`, and an item
/// path?
bool isShareUrl(String url, String baseUrl) {
  final u = Uri.tryParse(url);
  if (u == null || u.userInfo.isNotEmpty) return false;
  final host = u.host.toLowerCase();
  final scheme = u.scheme.toLowerCase();
  bool ours;
  if (scheme == 'sportpadi') {
    ours = host == 'sportpadi.com';
  } else if (scheme == 'https' || scheme == 'http') {
    final base = (Uri.tryParse(baseUrl)?.host ?? '').toLowerCase();
    final bare = base.startsWith('www.') ? base.substring(4) : base;
    ours = host == 'sportpadi.com' ||
        host == 'www.sportpadi.com' ||
        (bare.isNotEmpty && (host == bare || host == 'www.$bare'));
  } else {
    ours = false;
  }
  if (!ours) return false;
  String path;
  try {
    path = Uri.decodeComponent(u.path);
  } catch (_) {
    return false;
  }
  return isSharePath(path);
}

final _inText = RegExp(r'''(?:https?|sportpadi)://[^\s<>"')\]]+''',
    caseSensitive: false);

/// Our item links in a message body: in order, de-duplicated, trailing
/// punctuation dropped, at most [max].
List<String> shareUrlsIn(String text, String baseUrl, {int max = 3}) {
  final out = <String>[];
  for (final m in _inText.allMatches(text)) {
    final u = m.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), '');
    if (!out.contains(u) && isShareUrl(u, baseUrl)) out.add(u);
    if (out.length >= max) break;
  }
  return out;
}
