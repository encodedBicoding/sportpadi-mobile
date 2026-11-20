// The profile bio's cleaning and count — twin of the workspace's
// `packages/lib/src/bio.ts` (the server stores what that returns and counts
// it). Keep the two in step: the Edit profile counter must count what the
// server will count (review profile-header LOW).

/// Instagram's limit, in code points (what the database's `char_length` counts).
const bioMax = 150;

/// At most this many line breaks are kept; later ones become spaces.
const bioMaxBreaks = 4;

/// NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR — line breaks to text layout.
final _breaks = RegExp('[\u0085\u2028\u2029]');

/// C0 / C1 controls but the line break, DEL, and the bidi embeddings /
/// overrides / isolates (written as escapes: no invisible characters here).
final _strip = RegExp(
    '[\u0000-\u0009\u000B-\u001F\u007F-\u009F\u202A-\u202E\u2066-\u2069]');

/// What draws nothing: white space and zero-width / format characters.
final _invisible =
    RegExp('[\\s\u00AD\u034F\u180E\u200B-\u200F\u2060-\u2064\uFEFF]');

/// Length as the server counts it: code points.
int bioLength(String s) => s.runes.length;

/// The bio as it will be stored, or null for none (empty, or nothing
/// visible). Line breaks normalised, tabs as spaces, controls dropped,
/// trailing spaces off every line, blank lines folded to one, at most
/// [bioMaxBreaks] breaks, trimmed. Never shortens it.
String? normalizeBio(String? raw) {
  if (raw == null) return null;
  final lines = raw
      .replaceAll(RegExp(r'\r\n?'), '\n')
      .replaceAll(_breaks, '\n')
      .replaceAll('\t', ' ')
      .replaceAll(_strip, '')
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'\s+$'), ''))
      .toList();
  final kept = <String>[];
  for (final l in lines) {
    if (l.isEmpty && (kept.isEmpty || kept.last.isEmpty)) continue;
    kept.add(l);
  }
  while (kept.isNotEmpty && kept.last.isEmpty) {
    kept.removeLast();
  }
  final head = kept.take(bioMaxBreaks + 1).toList();
  final tail = kept
      .skip(bioMaxBreaks + 1)
      .where((l) => l.trim().isNotEmpty)
      .map((l) => l.trim());
  if (tail.isNotEmpty) head[head.length - 1] = [head.last, ...tail].join(' ');
  final out = head.join('\n').trim();
  return out.replaceAll(_invisible, '').isEmpty ? null : out;
}
