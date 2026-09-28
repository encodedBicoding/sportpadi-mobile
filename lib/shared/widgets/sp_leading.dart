import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The leading slot for every pushed screen's AppBar.
///
/// • Normal case: a real back button that pops the navigator — i.e. returns
///   to wherever the user actually came from, never to a hard-coded parent.
/// • Nothing to pop (the screen was the app's entry point: a share link, a
///   push-notification tap on a cold start, a join link): a Home button, so
///   the user is never stranded on a screen with no way out.
class SpLeading extends StatelessWidget {
  const SpLeading({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop() || Navigator.of(context).canPop();
    if (canPop) {
      return BackButton(
        color: color,
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            Navigator.of(context).maybePop();
          }
        },
      );
    }
    return IconButton(
      tooltip: 'Home',
      color: color,
      icon: const Icon(Icons.home_outlined),
      onPressed: () => context.go('/home'),
    );
  }
}

/// Go "back" from a flow that shouldn't leave its own screen on the stack
/// (e.g. after joining via a link): if there's history, pop; otherwise make
/// Home the base and open [path] on top of it so the new screen has a back.
void goWithHome(BuildContext context, String path) {
  if (context.canPop()) {
    context.pushReplacement(path);
  } else {
    context.go('/home');
    context.push(path);
  }
}
