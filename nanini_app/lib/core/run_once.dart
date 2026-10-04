/// Keys of the buttons whose last tap is still running, with when it began.
final _running = <String, DateTime>{};

/// Runs [action] for the button [key] unless that button's last tap is still
/// running: tapped twice while it saves (a slow connection), it would save
/// twice -- e.g. the same supplier added two times. Each button has its own
/// key, so a dialog it opens can still be used. A tap stuck for longer than
/// [stuckAfter] (it never finished) no longer blocks the button.
Future<void> runOnce(String key, Future<void> Function() action, {Duration stuckAfter = const Duration(minutes: 2)}) async {
  final started = _running[key];
  if (started != null && DateTime.now().difference(started) < stuckAfter) return;
  final me = DateTime.now();
  _running[key] = me;
  try {
    await action();
  } finally {
    if (identical(_running[key], me)) _running.remove(key);
  }
}
