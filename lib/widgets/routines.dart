import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/planner_scope.dart';
import '../util/dates.dart';
import '../util/palette.dart';
import 'common.dart';
import 'pickers.dart';

/// Edits a repeating block. Changes apply to every occurrence that hasn't
/// been individually changed.
Future<void> showRoutineEditor(BuildContext context, {Routine? routine}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RoutineEditor(routine: routine),
  );
}

/// Lists all routines with shortcuts to edit them.
Future<void> showRoutineManager(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _RoutineManager());
}

class _RoutineEditor extends StatefulWidget {
  const _RoutineEditor({this.routine});

  final Routine? routine;

  @override
  State<_RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<_RoutineEditor> {
  late final _title = TextEditingController(text: widget.routine?.title ?? '');
  late final _notes = TextEditingController(text: widget.routine?.notes ?? '');
  late int _start = widget.routine?.start ?? 7 * 60;
  late int _end = widget.routine?.end ?? 7 * 60 + 30;
  late List<int> _weekdays = widget.routine?.weekdays ?? const [1, 2, 3, 4, 5];
  late int _color = widget.routine?.color ?? plannerColors[1];
  late String? _goalId = widget.routine?.goalId;
  late DateTime _from = parseDateKey(widget.routine?.startDate ?? dateKey(today()));
  late DateTime? _until = widget.routine?.endDate == null
      ? null
      : parseDateKey(widget.routine!.endDate!);
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give the routine a name.');
      return;
    }
    if (_end <= _start) {
      setState(() => _error = 'End time must be after the start time.');
      return;
    }
    if (_until != null && _until!.isBefore(_from)) {
      setState(() => _error = 'The end date is before the start date.');
      return;
    }
    final store = PlannerScope.read(context);
    final base =
        widget.routine ??
        Routine(
          id: newId(),
          title: title,
          start: _start,
          end: _end,
          color: _color,
          startDate: dateKey(_from),
        );
    store.saveRoutine(
      base.copyWith(
        title: title,
        start: _start,
        end: _end,
        color: _color,
        notes: _notes.text.trim(),
        goalId: () => _goalId,
        weekdays: _weekdays,
        startDate: dateKey(_from),
        endDate: () => _until == null ? null : dateKey(_until!),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final store = PlannerScope.read(context);
    final navigator = Navigator.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove routine?'),
        content: const Text(
          'Stopping keeps past days in your history. Deleting removes every occurrence.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete everywhere'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'end'),
            child: const Text('Stop from today'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    choice == 'end'
        ? store.endRoutine(widget.routine!.id)
        : store.deleteRoutine(widget.routine!.id);
    navigator.pop();
  }

  Future<void> _pickDate({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _from : (_until ?? _from),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => from ? _from = picked : _until = picked);
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final goals = store.goals.where((g) => !g.completed || g.id == _goalId).toList();
    final fmt = DateFormat.yMMMd();

    return AlertDialog(
      title: Text(widget.routine == null ? 'New routine' : 'Edit routine'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                autofocus: widget.routine == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Routine',
                  hintText: 'e.g. Morning run, Deep work, Inbox zero',
                ),
              ),
              const SizedBox(height: 16),
              TimeRangePicker(
                start: _start,
                end: _end,
                onChanged: (s, e) => setState(() {
                  _start = s;
                  _end = e;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              Text('Repeat on', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              WeekdayPicker(weekdays: _weekdays, onChanged: (d) => setState(() => _weekdays = d)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(from: true),
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('From ${fmt.format(_from)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(from: false),
                    icon: const Icon(Icons.event_busy, size: 18),
                    label: Text(_until == null ? 'No end date' : 'Until ${fmt.format(_until!)}'),
                  ),
                  if (_until != null)
                    IconButton(
                      tooltip: 'Remove end date',
                      onPressed: () => setState(() => _until = null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Color', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              ColorPickerRow(selected: _color, onChanged: (c) => setState(() => _color = c)),
              if (goals.isNotEmpty) ...[
                const SizedBox(height: 16),
                GoalDropdown(
                  goals: goals,
                  value: _goalId,
                  onChanged: (id) => setState(() => _goalId = id),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.routine != null)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            child: const Text('Remove'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _RoutineManager extends StatelessWidget {
  const _RoutineManager();

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final use24h = store.settings.use24h;
    final routines = store.routines.toList()..sort((a, b) => a.start.compareTo(b.start));
    final todayKey = dateKey(today());
    final fmt = DateFormat.MMMd();

    return AlertDialog(
      title: const Text('Routines'),
      content: SizedBox(
        width: 520,
        child: routines.isEmpty
            ? Text(
                'Routines are blocks that repeat, like a morning run every weekday. '
                'Create one here, or choose "Repeat" when adding a block.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final r in routines)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Container(
                        width: 6,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(r.color),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      title: Text(r.title),
                      subtitle: Text(
                        [
                          '${describeWeekdays(r.weekdays)} · '
                              '${formatClock(r.start, use24h: use24h)}–${formatClock(r.end, use24h: use24h)}',
                          if (r.endDate != null && r.endDate!.compareTo(todayKey) < 0)
                            'ended ${fmt.format(parseDateKey(r.endDate!))}'
                          else if (r.endDate != null)
                            'until ${fmt.format(parseDateKey(r.endDate!))}'
                          else if (r.startDate.compareTo(todayKey) > 0)
                            'starts ${fmt.format(parseDateKey(r.startDate))}',
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showRoutineEditor(context, routine: r),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => showRoutineEditor(context),
          icon: const Icon(Icons.add),
          label: const Text('New routine'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
