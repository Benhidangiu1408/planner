import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/planner_scope.dart';
import '../data/planner_store.dart';
import '../platform/platform.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/routines.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final s = store.settings;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget row(String label, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          control,
        ],
      ),
    );

    DropdownButton<int> picker(
      int value,
      Iterable<int> options,
      String Function(int) label,
      ValueChanged<int> onChanged,
    ) => DropdownButton<int>(
      value: options.contains(value) ? value : options.first,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(12),
      onChanged: (v) => v == null ? null : onChanged(v),
      items: [for (final o in options) DropdownMenuItem(value: o, child: Text(label(o)))],
    );

    String hour(int h) => formatClock(h * 60, use24h: s.use24h);

    return Column(
      children: [
        const PageHeader(
          title: 'Settings',
          subtitle: 'Everything is saved automatically on this device.',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionCard(
                        icon: Icons.palette_outlined,
                        title: 'Appearance',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              runSpacing: 8,
                              children: [
                                Text('Theme', style: theme.textTheme.bodyLarge),
                                SegmentedButton<ThemePreference>(
                                  segments: const [
                                    ButtonSegment(
                                      value: ThemePreference.system,
                                      icon: Icon(Icons.brightness_auto_outlined),
                                      label: Text('Auto'),
                                    ),
                                    ButtonSegment(
                                      value: ThemePreference.light,
                                      icon: Icon(Icons.light_mode_outlined),
                                      label: Text('Light'),
                                    ),
                                    ButtonSegment(
                                      value: ThemePreference.dark,
                                      icon: Icon(Icons.dark_mode_outlined),
                                      label: Text('Dark'),
                                    ),
                                  ],
                                  selected: {s.theme},
                                  onSelectionChanged: (v) =>
                                      store.updateSettings(s.copyWith(theme: v.first)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text('Accent color', style: theme.textTheme.bodyLarge),
                            const SizedBox(height: 10),
                            AccentPicker(
                              selected: s.seedColor,
                              onChanged: (c) => store.updateSettings(s.copyWith(seedColor: c)),
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('24-hour clock'),
                              subtitle: Text(
                                'Times look like ${formatClock(14 * 60 + 30, use24h: s.use24h)}',
                              ),
                              value: s.use24h,
                              onChanged: (v) => store.updateSettings(s.copyWith(use24h: v)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SectionCard(
                        icon: Icons.view_timeline_outlined,
                        title: 'Day schedule',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            row(
                              'Timeline starts at',
                              picker(
                                s.dayStartHour,
                                List.generate(13, (i) => i),
                                hour,
                                (v) => store.updateSettings(
                                  s.copyWith(
                                    dayStartHour: v,
                                    dayEndHour: s.dayEndHour <= v ? v + 1 : null,
                                  ),
                                ),
                              ),
                            ),
                            row(
                              'Timeline ends at',
                              picker(
                                s.dayEndHour,
                                [for (var h = s.dayStartHour + 1; h <= 24; h++) h],
                                hour,
                                (v) => store.updateSettings(s.copyWith(dayEndHour: v)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Blocks outside these hours still show up; the timeline stretches to fit them.',
                              style: muted,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => showRoutineManager(context),
                                icon: const Icon(Icons.repeat),
                                label: Text('Routines (${store.routines.length})'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _RemindersCard(),
                      const SizedBox(height: 16),
                      const _StorageCard(),
                      const SizedBox(height: 16),
                      const _BackupCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------- reminders/focus

class _RemindersCard extends StatefulWidget {
  const _RemindersCard();

  @override
  State<_RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends State<_RemindersCard> {
  late NotificationAccess _access = notificationAccess();

  Future<void> _toggle(PlannerStore store, bool on) async {
    store.updateSettings(store.settings.copyWith(remindersEnabled: on));
    if (on && _access == NotificationAccess.notAsked) {
      final access = await requestNotificationAccess();
      if (mounted) setState(() => _access = access);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final s = store.settings;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final accessText = switch (_access) {
      NotificationAccess.granted => 'Browser notifications are allowed.',
      NotificationAccess.denied =>
        'Notifications are blocked for this site, so reminders appear inside the app only. '
            'You can allow them from the lock icon in the address bar.',
      NotificationAccess.notAsked => 'The browser will ask before showing notifications.',
      NotificationAccess.unsupported =>
        'This browser can\'t show notifications; reminders appear inside the app.',
    };

    return SectionCard(
      icon: Icons.notifications_outlined,
      title: 'Reminders & focus',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remind me before time blocks'),
            subtitle: Text(
              'Works while Planner is open in a tab (it can be in the background).',
              style: muted,
            ),
            value: s.remindersEnabled,
            onChanged: (v) => _toggle(store, v),
          ),
          if (s.remindersEnabled) ...[
            Row(
              children: [
                Expanded(child: Text('Notify', style: theme.textTheme.bodyLarge)),
                DropdownButton<int>(
                  value: const [0, 5, 10, 15, 30].contains(s.reminderLeadMinutes)
                      ? s.reminderLeadMinutes
                      : 5,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(12),
                  onChanged: (v) {
                    if (v != null) store.updateSettings(s.copyWith(reminderLeadMinutes: v));
                  },
                  items: [
                    for (final m in const [0, 5, 10, 15, 30])
                      DropdownMenuItem(
                        value: m,
                        child: Text(m == 0 ? 'When it starts' : '$m min before'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(accessText, style: muted),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (_access == NotificationAccess.notAsked)
                  OutlinedButton(
                    onPressed: () async {
                      final access = await requestNotificationAccess();
                      if (mounted) setState(() => _access = access);
                    },
                    child: const Text('Allow notifications'),
                  ),
                TextButton(
                  onPressed: () {
                    final shown = showSystemNotification(
                      'Planner reminder',
                      'This is what a reminder looks like.',
                    );
                    showMessage(
                      context,
                      shown
                          ? 'Test notification sent.'
                          : 'In-app reminder (browser notifications are off).',
                    );
                  },
                  child: const Text('Send a test'),
                ),
              ],
            ),
          ],
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Length of a free focus session', style: theme.textTheme.bodyLarge),
              ),
              DropdownButton<int>(
                value: const [15, 25, 45, 50, 60, 90].contains(s.focusMinutes)
                    ? s.focusMinutes
                    : 25,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                onChanged: (v) {
                  if (v != null) store.updateSettings(s.copyWith(focusMinutes: v));
                },
                items: [
                  for (final m in const [15, 25, 45, 50, 60, 90])
                    DropdownMenuItem(value: m, child: Text(formatDuration(m))),
                ],
              ),
            ],
          ),
          Text(
            'Focus sessions started from a block use the block\'s length instead.',
            style: muted,
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------- storage & sync

class _StorageCard extends StatefulWidget {
  const _StorageCard();

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard> {
  StorageEstimate? _estimate;
  bool? _persisted;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final estimate = await storageEstimate();
    final persisted = await isStoragePersisted();
    if (mounted) {
      setState(() {
        _estimate = estimate;
        _persisted = persisted;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    final syncSection = !supportsSyncFile
        ? Text(
            'A live sync file needs Chrome or Edge on a computer. In this browser, use '
            'Export and Import below to move your planner between devices.',
            style: muted,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Keep a copy of your planner in a file outside the browser. Put it in a '
                'OneDrive, Dropbox or Google Drive folder to use the same planner on other '
                'computers: changes are saved to the file as you work, and newer changes '
                'from the file are offered when you come back.',
                style: muted,
              ),
              const SizedBox(height: 12),
              switch (store.syncState) {
                SyncState.off => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _run(store.createAndConnectSyncFile),
                      icon: const Icon(Icons.note_add_outlined),
                      label: const Text('Create sync file…'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run(store.openAndConnectSyncFile),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Use existing file…'),
                    ),
                  ],
                ),
                SyncState.connected => _syncStatus(
                  context,
                  Icons.sync,
                  scheme.primary,
                  'Syncing with "${store.syncFileName}"',
                  [
                    TextButton(
                      onPressed: _busy ? null : () => _run(store.checkSyncFile),
                      child: const Text('Check for changes'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _run(store.disconnectSyncFile),
                      child: const Text('Stop syncing'),
                    ),
                  ],
                ),
                SyncState.needsPermission => _syncStatus(
                  context,
                  Icons.sync_lock,
                  scheme.tertiary,
                  'The browser needs permission again to write "${store.syncFileName}".',
                  [
                    FilledButton.tonal(
                      onPressed: _busy ? null : () => _run(store.reconnectSyncFile),
                      child: const Text('Reconnect'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _run(store.disconnectSyncFile),
                      child: const Text('Stop syncing'),
                    ),
                  ],
                ),
                SyncState.error => _syncStatus(
                  context,
                  Icons.sync_problem,
                  scheme.error,
                  'Sync file problem: ${store.syncError}',
                  [
                    FilledButton.tonal(
                      onPressed: _busy ? null : () => _run(store.reconnectSyncFile),
                      child: const Text('Try again'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _run(store.disconnectSyncFile),
                      child: const Text('Stop syncing'),
                    ),
                  ],
                ),
              },
            ],
          );

    return SectionCard(
      icon: Icons.storage_outlined,
      title: 'Storage & sync',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Saved in ${store.storageLabel == 'IndexedDB' ? 'this browser\'s database (IndexedDB)' : 'this browser\'s local storage'}'
            ' · ${_size(store.storedBytes)} of planner data',
            style: theme.textTheme.bodyLarge,
          ),
          if (_estimate != null && _estimate!.quota > 0)
            Text(
              'The browser allows this site up to ${_size(_estimate!.quota)} '
              '(${_size(_estimate!.usage)} used, including the app itself).',
              style: muted,
            ),
          const SizedBox(height: 10),
          if (_persisted == true)
            MetaLabel(
              icon: Icons.verified_user_outlined,
              text: 'Protected: the browser won\'t clear it to free up space.',
              color: scheme.primary,
            )
          else if (_persisted == false)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'The browser may clear site data when the disk is nearly full.',
                    style: muted,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final ok = await requestPersistentStorage();
                    await _refresh();
                    if (context.mounted) {
                      showMessage(
                        context,
                        ok ? 'Storage is now protected.' : 'The browser declined for now. Installing Planner as an app or using it more often usually helps.',
                      );
                    }
                  },
                  child: const Text('Protect it'),
                ),
              ],
            ),
          const Divider(height: 28),
          Text('Sync file', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          syncSection,
        ],
      ),
    );
  }

  Widget _syncStatus(
    BuildContext context,
    IconData icon,
    Color color,
    String text,
    List<Widget> actions,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }
}

// ---------------------------------------------------------------- backup

class _BackupCard extends StatelessWidget {
  const _BackupCard();

  Future<void> _export(BuildContext context, PlannerStore store) async {
    final json = store.exportJson();
    if (supportsFiles) {
      await downloadTextFile('planner-backup-${dateKey(today())}.json', json);
      if (context.mounted) showMessage(context, 'Backup downloaded.');
    } else {
      await Clipboard.setData(ClipboardData(text: json));
      if (context.mounted) showMessage(context, 'Backup copied to the clipboard.');
    }
  }

  Future<void> _copy(BuildContext context, PlannerStore store) async {
    await Clipboard.setData(ClipboardData(text: store.exportJson()));
    if (context.mounted) showMessage(context, 'Backup copied to the clipboard.');
  }

  Future<void> _restore(BuildContext context, PlannerStore store, String? source) async {
    if (source == null || source.trim().isEmpty || !context.mounted) return;
    final ok = await confirmAction(
      context,
      title: 'Replace all data?',
      message: 'Everything currently in the planner will be replaced by the backup.',
      confirmLabel: 'Replace',
    );
    if (!ok || !context.mounted) return;
    try {
      store.importJson(source);
      showMessage(context, 'Backup restored.');
    } on FormatException catch (e) {
      showMessage(context, e.message);
    }
  }

  Future<void> _paste(BuildContext context, PlannerStore store) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste a backup'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 8,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(hintText: '{ "version": 2, ... }'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (context.mounted) await _restore(context, store, text);
  }

  Future<void> _deleteAll(BuildContext context, PlannerStore store) async {
    final ok = await confirmAction(
      context,
      title: 'Delete everything?',
      message:
          'All blocks, routines, tasks, goals, habits, focus sessions and notes will be erased. '
          'Export a backup first if you might want them back.',
      confirmLabel: 'Delete all',
    );
    if (ok) store.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return SectionCard(
      icon: Icons.save_outlined,
      title: 'Backup & data',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'A backup is a single JSON file with everything in it. Private windows and other '
            'browsers start empty, so export one now and then.',
            style: muted,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _export(context, store),
                icon: const Icon(Icons.download),
                label: const Text('Export backup'),
              ),
              if (supportsFiles)
                OutlinedButton.icon(
                  onPressed: () async {
                    final text = await pickTextFile();
                    if (context.mounted) await _restore(context, store, text);
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import from file'),
                ),
              OutlinedButton.icon(
                onPressed: () => _paste(context, store),
                icon: const Icon(Icons.content_paste),
                label: const Text('Paste backup'),
              ),
              TextButton.icon(
                onPressed: () => _copy(context, store),
                icon: const Icon(Icons.copy),
                label: const Text('Copy as JSON'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(
            '${store.blocks.length} blocks · ${store.routines.length} routines · '
            '${store.tasks.length} tasks · ${store.goals.length} goals · '
            '${store.habits.length} habits · ${store.sessions.length} focus sessions',
            style: muted,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              onPressed: () => _deleteAll(context, store),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Delete all data'),
            ),
          ),
        ],
      ),
    );
  }
}
