import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/widgets/sheet_scroll.dart';

/// Opens a bottom sheet the 2026 way. Every sheet in the app goes through
/// here, so they all look and behave the same wherever they're opened from:
///
/// * on the ROOT navigator, so the sheet always sits over the whole screen —
///   the dock and the ad strip included — never underneath or beside them;
/// * page-canvas colour, 28 rounded top corners and one grabber (fields and
///   cards, which are `surface`, read clearly on it in light and dark);
/// * clear of the notch at the top and the home indicator at the bottom,
///   lifted above the keyboard, and never taller than ~92% of the screen —
///   long content scrolls, and a pull-down at the top still closes it.
///
/// [framed] false hands the whole sheet to [builder] (it draws its own
/// frame — the ticket, the scanner result); it still gets the root
/// navigator, the safe area and full-height room.
///
/// [scrollable] false is for a sheet whose body brings its own list
/// (a search picker with an `Expanded` ListView): the frame gives it a
/// bounded height instead of a scroll view.
Future<T?> showSpSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool framed = true,
  bool scrollable = true,
  bool isDismissible = true,
  bool enableDrag = true,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 4, 20, 20),
  Color? color,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: false,
    elevation: 0,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8C0E1411),
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => framed
        ? SpSheet(
            scrollable: scrollable,
            padding: padding,
            color: color,
            child: Builder(builder: builder),
          )
        : Builder(builder: builder),
  );
}

/// How content that can sit either on a page or inside a sheet runs a
/// navigation (or opens a follow-up sheet). Inside a sheet it closes the
/// sheet first, then runs the action with a context that is still mounted
/// (the page's), so a pushed route never lands underneath the sheet — see
/// [closeSheetThen]. Widgets take it as an optional `launch`; null means
/// "I'm on a page": run the action with my own context ([runFromSheet]).
typedef SheetLaunch = void Function(void Function(BuildContext context) action);

/// A [SheetLaunch] for content inside a [showSpSheet] sheet opened from
/// [pageContext]: pops the sheet ([sheetContext] is any context inside it),
/// then runs the action on the page.
SheetLaunch closeSheetThen(
        BuildContext sheetContext, BuildContext pageContext) =>
    (action) {
      if (!sheetContext.mounted) return; // the sheet is already gone
      Navigator.of(sheetContext).pop();
      if (pageContext.mounted) action(pageContext);
    };

/// Runs [action] through [launch] when given (content inside a sheet), or
/// straight away with [context] (content on a page).
void runFromSheet(BuildContext context, SheetLaunch? launch,
    void Function(BuildContext context) action) {
  if (launch == null) {
    action(context);
  } else {
    launch(action);
  }
}

/// The frame [showSpSheet] draws around a sheet's content. Usable on its own
/// for a `framed: false` sheet that still wants the standard look.
class SpSheet extends StatelessWidget {
  const SpSheet({
    super.key,
    required this.child,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 20),
    this.color,
  });

  final Widget child;
  final bool scrollable;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      // Lift the whole sheet over the keyboard (the modal route doesn't).
      padding: EdgeInsets.only(bottom: keyboard),
      child: LayoutBuilder(builder: (context, c) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                c.maxHeight.isFinite ? c.maxHeight * 0.92 : double.infinity,
          ),
          child: Material(
            color: color ?? p.bg,
            surfaceTintColor: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            child: SafeArea(
              top: false,
              // With the keyboard up the inset is already below us.
              bottom: keyboard == 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 10, bottom: 12),
                    child: SpGrabber(),
                  ),
                  Flexible(
                    child: scrollable
                        ? SheetScrollView(padding: padding, child: child)
                        : Padding(padding: padding, child: child),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// The sheet handle: a short rounded bar.
class SpGrabber extends StatelessWidget {
  const SpGrabber({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: context.palette.line,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// The top of a sheet: icon tile, title, one quiet line, optional trailing.
class SpSheetHeader extends StatelessWidget {
  const SpSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconBg,
    this.iconFg,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconBg;
  final Color? iconFg;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        if (icon != null) ...[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg ?? p.accentTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 21, color: iconFg ?? p.greenText),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: p.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2)),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle!,
                  style:
                      TextStyle(color: p.muted, fontSize: 12.5, height: 1.35)),
            ],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}
