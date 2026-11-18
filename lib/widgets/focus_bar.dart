import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/planner_scope.dart';
import '../platform/platform.dart';
import '../util/dates.dart';

String formatStopwatch(int ms) {
  final total = ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Shows the running focus timer at the bottom of the app.
class FocusBar extends StatefulWidget {
  const FocusBar({super.key});

  @override
  State<FocusBar> createState() => _FocusBarState();
}

class _FocusBarState extends State<FocusBar> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Ticks once a second only while a timer is actually running.
  void _syncTicker(bool running) {
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  void _alertIfDue(int elapsedMs) {
    final store = PlannerScope.read(context);
    final focus = store.activeFocus;
    if (focus == null || focus.alerted || elapsedMs < focus.targetMinutes * 60000) return;
    // Defer: this runs during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      store.markFocusAlerted();
      final body = '${formatDuration(focus.targetMinutes)} of "${focus.title}" done. Take a break?';
      showSystemNotification("Time's up", body);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text("Time's up! $body"), behavior: SnackBarBehavior.floating),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final focus = store.activeFocus;
    _syncTicker(focus?.running ?? false);
    if (focus == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final elapsed = focus.elapsedMs(DateTime.now().millisecondsSinceEpoch);
    final target = focus.targetMinutes * 60000;
    final over = elapsed >= target;
    _alertIfDue(elapsed);

    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    focus.running ? Icons.timer : Icons.pause_circle,
                    color: scheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          focus.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        Text(
                          over
                              ? '${formatStopwatch(elapsed)} · ${formatStopwatch(elapsed - target)} over'
                              : '${formatStopwatch(elapsed)} of ${formatDuration(focus.targetMinutes)}'
                                    '${focus.running ? '' : ' · paused'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: focus.running ? 'Pause' : 'Resume',
                    onPressed: focus.running ? store.pauseFocus : store.resumeFocus,
                    icon: Icon(focus.running ? Icons.pause : Icons.play_arrow),
                    color: scheme.onPrimaryContainer,
                  ),
                  IconButton(
                    tooltip: 'Finish and log time',
                    onPressed: () {
                      final session = store.stopFocus();
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              session == null
                                  ? 'Under a minute, nothing logged.'
                                  : 'Logged ${formatDuration(session.minutes)} of focus.',
                            ),
                          ),
                        );
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    color: scheme.onPrimaryContainer,
                  ),
                  IconButton(
                    tooltip: 'Discard',
                    onPressed: () => store.stopFocus(save: false),
                    icon: const Icon(Icons.close),
                    color: scheme.onPrimaryContainer,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: (elapsed / target).clamp(0.0, 1.0),
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
                color: over ? scheme.tertiary : scheme.primary,
                backgroundColor: scheme.onPrimaryContainer.withValues(alpha: 0.12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
