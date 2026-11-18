import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/planner_scope.dart';
import '../util/dates.dart';
import '../util/palette.dart';
import 'common.dart';
import 'pickers.dart';
import 'routines.dart';

// ------------------------------------------------------------- time block

Future<void> showBlockEditor(
  BuildContext context, {
  required String date,
  TimeBlock? block,
  int start = 9 * 60,
  int end = 10 * 60,
  String title = '',
  String? goalId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BlockEditor(
      date: date,
      block: block,
      start: start,
      end: end,
      title: title,
      goalId: goalId,
    ),
  );
}

enum _Repeat { none, daily, weekdays, custom }

class _BlockEditor extends StatefulWidget {
  const _BlockEditor({
    required this.date,
    required this.block,
    required this.start,
    required this.end,
    required this.title,
    required this.goalId,
  });

  final String date;
  final TimeBlock? block;
  final int start;
  final int end;
  final String title;
  final String? goalId;

  @override
  State<_BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends State<_BlockEditor> {
  late final _title = TextEditingController(text: widget.block?.title ?? widget.title);
  late final _notes = TextEditingController(text: widget.block?.notes ?? '');
  late int _start = widget.block?.start ?? widget.start;
  late int _end = widget.block?.end ?? widget.end;
  late String? _goalId = widget.block?.goalId ?? widget.goalId;
  late bool _done = widget.block?.done ?? false;
  late int _color =
      widget.block?.color ??
      PlannerScope.read(context).goalById(_goalId)?.color ??
      plannerColors.first;
  _Repeat _repeat = _Repeat.none;
  List<int> _customDays = const [];
  String? _error;

  bool get _isNew => widget.block == null;
  bool get _isRoutineOccurrence => widget.block?.routineId != null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<int>? get _repeatDays => switch (_repeat) {
    _Repeat.none => null,
    _Repeat.daily => const [],
    _Repeat.weekdays => const [1, 2, 3, 4, 5],
    _Repeat.custom => _customDays,
  };

  TimeBlock? _build() {
    if (_end <= _start) {
      setState(() => _error = 'End time must be after the start time.');
      return null;
    }
    final title = _title.text.trim();
    final base =
        widget.block ??
        TimeBlock(id: newId(), date: widget.date, start: 0, end: 0, title: '', color: _color);
    return base.copyWith(
      start: _start,
      end: _end,
      title: title.isEmpty ? 'Untitled' : title,
      notes: _notes.text.trim(),
      color: _color,
      done: _done,
      goalId: () => _goalId,
    );
  }

  void _save() {
    final block = _build();
    if (block == null) return;
    final store = PlannerScope.read(context);
    final days = _repeatDays;
    if (days != null && !_isRoutineOccurrence) {
      if (!_isNew) store.saveBlock(block);
      store.makeRoutine(block, days);
    } else {
      store.saveBlock(block);
    }
    Navigator.pop(context);
  }

  void _focus() {
    final block = _build();
    if (block == null) return;
    final store = PlannerScope.read(context);
    // Save first so the timer is attached to the stored block.
    store.startFocus(block: store.saveBlock(block));
    Navigator.pop(context);
  }

  void _delete() {
    final store = PlannerScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final removed = store.deleteBlock(widget.block!.id);
    Navigator.pop(context);
    if (removed != null) {
      showUndoSnackBar(messenger, 'Deleted "${removed.title}"', () => store.restoreBlock(removed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final use24h = store.settings.use24h;
    final goals = store.goals.where((g) => !g.completed || g.id == _goalId).toList();
    final routine = store.routineById(widget.block?.routineId);
    final focused = widget.block == null ? 0 : store.focusMinutesForBlock(widget.block!.id);

    return AlertDialog(
      title: Text(_isNew ? 'New time block' : 'Edit time block'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (routine != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.repeat, size: 18, color: scheme.onSecondaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Part of "${routine.title}": ${describeWeekdays(routine.weekdays).toLowerCase()} at '
                              '${formatClock(routine.start, use24h: use24h)}. '
                              'Changes here only affect this day.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              showRoutineEditor(context, routine: routine);
                            },
                            child: const Text('Edit routine'),
                          ),
                          TextButton(
                            onPressed: () async {
                              final navigator = Navigator.of(context);
                              final ok = await confirmAction(
                                context,
                                title: 'Stop repeating?',
                                message:
                                    '"${routine.title}" will no longer appear from today on. '
                                    'Past days keep their blocks.',
                                confirmLabel: 'Stop',
                              );
                              if (!ok) return;
                              store.endRoutine(routine.id);
                              navigator.pop();
                            },
                            child: const Text('Stop repeating'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: _title,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'What will you do?'),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              TimeRangePicker(
                start: _start,
                end: _end,
                error: _error,
                onChanged: (s, e) => setState(() {
                  _start = s;
                  _end = e;
                  _error = null;
                }),
              ),
              if (focused > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: MetaLabel(
                    icon: Icons.timer_outlined,
                    text:
                        '${formatDuration(focused)} focused of ${formatDuration(_end - _start)} planned',
                  ),
                ),
              if (!_isRoutineOccurrence) ...[
                const SizedBox(height: 16),
                Text('Repeat', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (value, label) in const [
                      (_Repeat.none, "Doesn't repeat"),
                      (_Repeat.daily, 'Every day'),
                      (_Repeat.weekdays, 'Weekdays'),
                      (_Repeat.custom, 'Custom'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _repeat == value,
                        onSelected: (_) => setState(() {
                          _repeat = value;
                          if (value == _Repeat.custom && _customDays.isEmpty) {
                            _customDays = [parseDateKey(widget.block?.date ?? widget.date).weekday];
                          }
                        }),
                      ),
                  ],
                ),
                if (_repeat == _Repeat.custom) ...[
                  const SizedBox(height: 8),
                  WeekdayPicker(
                    weekdays: _customDays,
                    onChanged: (d) => setState(() => _customDays = d),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Text('Color', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              ColorPickerRow(selected: _color, onChanged: (c) => setState(() => _color = c)),
              if (goals.isNotEmpty) ...[
                const SizedBox(height: 16),
                GoalDropdown(
                  goals: goals,
                  value: _goalId,
                  onChanged: (id) => setState(() {
                    _goalId = id;
                    final goal = store.goalById(id);
                    if (_isNew && goal != null) _color = goal.color;
                  }),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
              if (!_isNew)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _done,
                  onChanged: (v) => setState(() => _done = v ?? false),
                  title: const Text('Done'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (!_isNew)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: Text(_isRoutineOccurrence ? 'Skip this day' : 'Delete'),
          ),
        if (_repeat == _Repeat.none)
          TextButton.icon(
            onPressed: _focus,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Focus'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// ------------------------------------------------------------------- task

Future<void> showTaskEditor(BuildContext context, Task task) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TaskEditor(task: task),
  );
}

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({required this.task});

  final Task task;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final _title = TextEditingController(text: widget.task.title);
  late DateTime _date = parseDateKey(widget.task.date);
  late bool _important = widget.task.important;
  late String? _goalId = widget.task.goalId;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    PlannerScope.read(context).saveTask(
      widget.task.copyWith(
        title: title,
        date: dateKey(_date),
        important: _important,
        goalId: () => _goalId,
      ),
    );
    Navigator.pop(context);
  }

  void _delete() {
    final store = PlannerScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final removed = store.deleteTask(widget.task.id);
    Navigator.pop(context);
    if (removed != null) {
      showUndoSnackBar(messenger, 'Task deleted', () => store.saveTask(removed));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final goals = store.goals.where((g) => !g.completed || g.id == _goalId).toList();
    final now = today();

    return AlertDialog(
      title: const Text('Edit task'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Task'),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(DateFormat.yMMMEd().format(_date)),
                  ),
                  for (final (label, day) in [
                    ('Today', now),
                    ('Tomorrow', addDays(now, 1)),
                    ('Next week', startOfWeek(addDays(now, 7))),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: isSameDay(_date, day),
                      onSelected: (_) => setState(() => _date = day),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _important,
                onChanged: (v) => setState(() => _important = v),
                title: const Text('Priority'),
                subtitle: const Text('Starred tasks stay at the top of the list'),
              ),
              if (goals.isNotEmpty) ...[
                const SizedBox(height: 8),
                GoalDropdown(
                  goals: goals,
                  value: _goalId,
                  onChanged: (id) => setState(() => _goalId = id),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _delete,
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: const Text('Delete'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Small dialog to add a task to a given day.
Future<void> showQuickAddTask(BuildContext context, String date) async {
  final controller = TextEditingController();
  final title = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Add a task · ${DateFormat.MMMEd().format(parseDateKey(date))}'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Task'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (title != null && title.trim().isNotEmpty && context.mounted) {
    PlannerScope.read(context).addTask(title.trim(), date);
  }
}

// ------------------------------------------------------------------ habit

Future<void> showHabitEditor(BuildContext context, {Habit? habit}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _HabitEditor(habit: habit),
  );
}

class _HabitEditor extends StatefulWidget {
  const _HabitEditor({this.habit});

  final Habit? habit;

  @override
  State<_HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<_HabitEditor> {
  late final _name = TextEditingController(text: widget.habit?.name ?? '');
  late int _color =
      widget.habit?.color ??
      plannerColors[(PlannerScope.read(context).habits.length + 1) % plannerColors.length];
  late List<int> _weekdays = widget.habit?.weekdays ?? const [];
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give your habit a name.');
      return;
    }
    final store = PlannerScope.read(context);
    final existing = widget.habit;
    store.saveHabit(
      existing != null
          ? existing.copyWith(name: name, color: _color, weekdays: _weekdays)
          : Habit(
              id: newId(),
              name: name,
              color: _color,
              weekdays: _weekdays,
              createdOn: dateKey(today()),
            ),
    );
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final store = PlannerScope.read(context);
    final navigator = Navigator.of(context);
    final ok = await confirmAction(
      context,
      title: 'Delete habit?',
      message: 'This removes "${widget.habit!.name}" and its whole history.',
    );
    if (!ok) return;
    store.deleteHabit(widget.habit!.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.habit == null ? 'New habit' : 'Edit habit'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Habit',
                  hintText: 'e.g. Read 10 pages',
                  errorText: _error,
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              Text('Color', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              ColorPickerRow(selected: _color, onChanged: (c) => setState(() => _color = c)),
              const SizedBox(height: 16),
              Text('Repeat on', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              WeekdayPicker(weekdays: _weekdays, onChanged: (d) => setState(() => _weekdays = d)),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.habit != null)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
