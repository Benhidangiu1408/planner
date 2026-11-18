import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/planner_scope.dart';
import '../platform/platform.dart';
import '../util/dates.dart';

/// While the app is open, notifies shortly before each time block starts.
/// Uses a browser notification when allowed, and always an in-app message.
class ReminderWatcher extends StatefulWidget {
  const ReminderWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<ReminderWatcher> createState() => _ReminderWatcherState();
}

class _ReminderWatcherState extends State<ReminderWatcher> {
  Timer? _timer;
  final _sent = <String>{};

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    final store = PlannerScope.read(context);
    final settings = store.settings;
    if (!settings.remindersEnabled) return;
    final now = DateTime.now();
    final key = dateKey(now);
    final minute = now.hour * 60 + now.minute;
    final lead = settings.reminderLeadMinutes;

    for (final b in store.blocksOn(key)) {
      if (b.done || minute < b.start - lead || minute > b.start) continue;
      // Keyed by time and title so a block that gets saved (new id) isn't repeated.
      if (!_sent.add('$key|${b.start}|${b.title}')) continue;
      final inMinutes = b.start - minute;
      final title = inMinutes <= 0 ? 'Starting now: ${b.title}' : 'In $inMinutes min: ${b.title}';
      final body =
          '${formatClock(b.start, use24h: settings.use24h)} – ${formatClock(b.end, use24h: settings.use24h)}';
      showSystemNotification(title, body);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            persist: false,
            duration: const Duration(seconds: 10),
            content: Text('$title ($body)'),
            action: SnackBarAction(
              label: 'Start focus',
              onPressed: () => store.startFocus(block: b),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
