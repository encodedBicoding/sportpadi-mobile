// The group page's pill tab track: tabs share the width when they fit, and
// the track scrolls sideways (labels never squeezed) when they don't — the
// body follows the selected tab.
//
//   flutter test test/shared/sp_tab_track_test.dart
//
// Widths are derived from the labels' measured size (the test font isn't the
// app font), so each case sits just either side of "fits".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sportpadi_mobile/shared/widgets/sp_tab_track.dart';

const three = ['Events', 'Teams', 'Tournaments'];
const four = ['Events', 'Teams', 'Tournaments', 'Leagues'];

/// Page gutters (20 + 20) and the track's inner padding (4 + 4).
const chrome = 48.0;

/// Inner width the labels need at scale 1 (bold label + 16px either side).
double need(List<String> labels) {
  var w = 0.0;
  for (final l in labels) {
    final tp = TextPainter(
      text: TextSpan(text: l, style: SpTabTrack.labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    w += tp.width + SpTabTrack.labelPadding * 2;
  }
  return w;
}

/// A phone-shaped screen: the track (20px gutters, like the group page) and
/// a body that shows the selected tab's name.
Future<void> pumpTrack(WidgetTester tester, List<String> labels, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: DefaultTabController(
      length: labels.length,
      child: Builder(builder: (context) {
        final c = DefaultTabController.of(context);
        return Scaffold(
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
              child: SpTabTrack(labels: labels),
            ),
            AnimatedBuilder(
              animation: c,
              builder: (_, __) => Text('body:${labels[c.index]}'),
            ),
          ]),
        );
      }),
    ),
  ));
  await tester.pumpAndSettle();
}

bool scrolls(WidgetTester tester) => tester.widget<TabBar>(find.byType(TabBar)).isScrollable;

/// A tab's slot — TabBar wraps each [Tab] (just the label) in
/// Center(Padding(labelPadding)), which takes the equal share when the tabs
/// fill the track and hugs label + padding when they scroll.
double slot(WidgetTester tester, String label) =>
    tester.getSize(find.ancestor(of: find.widgetWithText(Tab, label), matching: find.byType(Center)).first).width;

void main() {
  testWidgets('tabs that fit share the width evenly, no scrolling', (tester) async {
    await pumpTrack(tester, three, need(three) + chrome + 24);
    expect(scrolls(tester), isFalse);
    final widths = [for (final l in three) slot(tester, l)];
    expect(widths.map((w) => w.toStringAsFixed(1)).toSet().length, 1, reason: 'equal shares: $widths');
  });

  testWidgets('a fourth tab that does not fit scrolls instead of shrinking', (tester) async {
    // Room for three, not for four: the group page with Leagues on a phone.
    await pumpTrack(tester, four, need(three) + chrome + 24);
    expect(scrolls(tester), isTrue);

    // Labels keep their full size — each tab is at least its label + padding.
    for (final l in four) {
      final tp = TextPainter(text: TextSpan(text: l, style: SpTabTrack.labelStyle), textDirection: TextDirection.ltr)
        ..layout();
      expect(slot(tester, l), greaterThanOrEqualTo(tp.width + SpTabTrack.labelPadding * 2 - 0.5), reason: l);
      // …and the label itself isn't squeezed.
      expect(tester.getSize(find.text(l)).width, greaterThanOrEqualTo(tp.width - 0.5), reason: l);
    }

    // The last tab starts off the edge of the track…
    final track = tester.getRect(find.byType(SpTabTrack));
    expect(tester.getRect(find.text('Leagues')).right, greaterThan(track.right));

    // …tapping its visible part selects it, the body follows, and the
    // track scrolls it fully into view.
    final visible = tester.getRect(find.text('Leagues'));
    await tester.tapAt(Offset(track.right - 12, visible.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('body:Leagues'), findsOneWidget);
    expect(tester.getRect(find.text('Leagues')).right, lessThanOrEqualTo(track.right));

    // Back to the first tab: drag the track back and tap it.
    await tester.drag(find.byType(TabBar), const Offset(600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    expect(find.text('body:Events'), findsOneWidget);
  });

  testWidgets('four tabs on a wide screen fit without scrolling', (tester) async {
    await pumpTrack(tester, four, need(four) + chrome + 24);
    expect(scrolls(tester), isFalse);
  });

  testWidgets('large text makes the track scroll rather than clip', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpTrack(tester, three, need(three) + chrome + 24);
    expect(scrolls(tester), isTrue);
  });
}
