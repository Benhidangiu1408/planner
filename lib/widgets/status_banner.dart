import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/planner_scope.dart';
import '../data/planner_store.dart';

/// Surfaces save problems and sync-file decisions at the top of the app.
class StatusBanner extends StatefulWidget {
  const StatusBanner({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  State<StatusBanner> createState() => _StatusBannerState();
}

class _StatusBannerState extends State<StatusBanner> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back to the tab: pick up changes made on another computer.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (mounted) PlannerScope.read(context).checkSyncFile();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    Widget banner(IconData icon, String text, List<Widget> actions, {bool warning = false}) =>
        MaterialBanner(
          leading: Icon(icon, color: warning ? scheme.error : scheme.primary),
          content: Text(text),
          backgroundColor: warning ? scheme.errorContainer : scheme.secondaryContainer,
          actions: actions,
        );

    final incoming = store.incomingSyncSavedAt;
    if (incoming != null) {
      final when = DateFormat.yMMMd().add_Hm().format(
        DateTime.fromMillisecondsSinceEpoch(incoming),
      );
      return banner(
        Icons.sync_problem,
        'Your sync file has newer changes (saved $when), probably from another computer.',
        [
          TextButton(
            onPressed: store.rejectIncomingSync,
            child: const Text("Keep this browser's data"),
          ),
          FilledButton(onPressed: store.acceptIncomingSync, child: const Text('Load them')),
        ],
      );
    }
    if (store.syncState == SyncState.needsPermission) {
      return banner(
        Icons.sync_lock,
        'Allow access to "${store.syncFileName}" again to keep your sync file up to date.',
        [
          TextButton(onPressed: widget.onOpenSettings, child: const Text('Settings')),
          FilledButton(onPressed: store.reconnectSyncFile, child: const Text('Reconnect')),
        ],
      );
    }
    if (store.saveError != null) {
      return banner(
        Icons.error_outline,
        "Couldn't save your latest changes: ${store.saveError}. Export a backup to be safe.",
        [TextButton(onPressed: widget.onOpenSettings, child: const Text('Settings'))],
        warning: true,
      );
    }
    if (store.syncState == SyncState.error) {
      return banner(Icons.sync_disabled, 'The sync file is not being updated: ${store.syncError}', [
        TextButton(onPressed: widget.onOpenSettings, child: const Text('Settings')),
      ], warning: true);
    }
    return const SizedBox.shrink();
  }
}
