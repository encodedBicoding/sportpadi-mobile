import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// How long [text] is the way the SERVER counts it: in Unicode code points
/// (`Array.from(s).length` there). A text box's own `maxLength` counts what a
/// person sees as one character instead — a flag, a skin-toned emoji or a
/// tone-marked Yoruba vowel is 1 to the box and 2–7 to the server, so a
/// caption the box let through could be refused after the whole upload.
int highlightTextLength(String text) => text.runes.length;

/// Keeps a text box within [max] characters, counted as the server counts
/// them ([highlightTextLength]). What an edit adds beyond that is left out —
/// whole characters only, never half an emoji — and the text around it
/// stays as it was; an edit of which nothing fits changes nothing.
class HighlightTextLimit extends TextInputFormatter {
  HighlightTextLimit(this.max);
  final int max;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (highlightTextLength(text) <= max) return newValue;
    final old = oldValue.text;

    // What this edit put in: the part of the new text between what it still
    // shares with the old one at the front and at the back. (Neither end may
    // stop between the two halves of one code point.)
    final shortest = old.length < text.length ? old.length : text.length;
    var head = 0;
    while (head < shortest && old.codeUnitAt(head) == text.codeUnitAt(head)) {
      head++;
    }
    if (head > 0 && _isLeadSurrogate(text.codeUnitAt(head - 1))) head--;
    var tail = 0;
    while (tail < shortest - head &&
        old.codeUnitAt(old.length - 1 - tail) ==
            text.codeUnitAt(text.length - 1 - tail)) {
      tail++;
    }
    if (tail > 0 && _isTrailSurrogate(text.codeUnitAt(text.length - tail))) {
      tail--;
    }

    final before = text.substring(0, head);
    final added = text.substring(head, text.length - tail);
    final after = text.substring(text.length - tail);
    // Nothing was put in, so the text was too long before this edit: let it
    // shrink.
    if (added.isEmpty) return newValue;
    var room = max - highlightTextLength(before) - highlightTextLength(after);
    final kept = StringBuffer();
    for (final char in added.characters) {
      room -= highlightTextLength(char);
      if (room < 0) break;
      kept.write(char);
    }
    // None of it fits (typing at the limit): nothing changes, the cursor
    // included.
    if (kept.isEmpty) return oldValue;
    return TextEditingValue(
      text: '$before$kept$after',
      selection: TextSelection.collapsed(offset: head + kept.length),
    );
  }
}

bool _isLeadSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isTrailSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
