/// The share sheet's other-apps row: one link per app, built from the item's
/// title (or the page's own share text) and its URL — the web's
/// `components/share/intents.ts`, string for string. Pure Dart.
library;

enum ShareApp { whatsapp, x, facebook, telegram, sms, email }

String _enc(String s) => Uri.encodeComponent(s);

/// The words without the link, and the whole message (words + link, once).
/// [text] is a page's own wording (a call for teams, a ticket's line) and may
/// already hold the link — then it isn't added twice.
({String words, String message}) shareMessage(
    {required String url, required String title, String? text}) {
  final t = (text ?? '').trim();
  final body = t.isNotEmpty ? t : title.trim();
  if (body.contains(url)) {
    final words = body.replaceFirst(url, '').trim();
    return (words: words.isEmpty ? title : words, message: body);
  }
  return (words: body, message: body.isEmpty ? url : '$body $url');
}

/// The link that opens [app] with the message filled in.
String shareIntentUrl(ShareApp app,
    {required String url, required String title, String? text}) {
  final m = shareMessage(url: url, title: title, text: text);
  switch (app) {
    case ShareApp.whatsapp:
      return 'https://wa.me/?text=${_enc(m.message)}';
    case ShareApp.x:
      return 'https://twitter.com/intent/tweet?text=${_enc(m.words)}&url=${_enc(url)}';
    case ShareApp.facebook:
      return 'https://www.facebook.com/sharer/sharer.php?u=${_enc(url)}';
    case ShareApp.telegram:
      return 'https://t.me/share/url?url=${_enc(url)}&text=${_enc(m.words)}';
    case ShareApp.email:
      return 'mailto:?subject=${_enc(title)}&body=${_enc(m.message)}';
    case ShareApp.sms:
      // `?&body=` is the form both iOS and Android read.
      return 'sms:?&body=${_enc(m.message)}';
  }
}
