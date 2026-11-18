import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/planner_scope.dart';
import '../../util/dates.dart';
import '../../widgets/common.dart';
import '../../widgets/editors.dart';
import '../../widgets/task_drag.dart';

// ------------------------------------------------------------------ tasks

class TasksPanel extends StatefulWidget {
  const TasksPanel({super.key, required this.date, this.draggable = false});

  final DateTime date;

  /// Whether tasks can be dragged onto the timeline next to this panel.
  final bool draggable;

  @override
  State<TasksPanel> createState() => _TasksPanelState();
}

class _TasksPanelState extends State<TasksPanel> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final title = _input.text.trim();
    if (title.isEmpty) return;
    PlannerScope.read(context).addTask(title, dateKey(widget.date));
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final key = dateKey(widget.date);
    final tasks = store.tasksOn(key);
    final done = tasks.where((t) => t.done).length;
    final overdue = isSameDay(widget.date, today()) ? store.overdueTasks(key) : const <Task>[];

    return SectionCard(
      icon: Icons.task_alt,
      title: 'Tasks',
      trailing: tasks.isEmpty
          ? null
          : Text(
              '$done of ${tasks.length} done',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (overdue.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.history, size: 18, color: theme.colorScheme.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${overdue.length} unfinished from earlier days',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => store.moveTasks(overdue.map((t) => t.id), key),
                    child: const Text('Move to today'),
                  ),
                ],
              ),
            ),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Nothing yet. What are the few things that would make this day a win?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final t in tasks)
            if (widget.draggable && !t.done)
              TaskDraggable(
                task: t,
                child: _TaskRow(task: t, goal: store.goalById(t.goalId)),
              )
            else
              _TaskRow(task: t, goal: store.goalById(t.goalId)),
          if (widget.draggable && tasks.any((t) => !t.done))
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                'Tip: drag a task onto the schedule to block time for it.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 4),
          TextField(
            controller: _input,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Add a task…',
              prefixIcon: const Icon(Icons.add),
              suffixIcon: IconButton(
                tooltip: 'Add',
                onPressed: _add,
                icon: const Icon(Icons.keyboard_return, size: 18),
              ),
            ),
            onSubmitted: (_) => _add(),
            // Keep focus so several tasks can be typed in a row.
            onEditingComplete: () {},
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.goal});

  final Task task;
  final Goal? goal;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.read(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    void scheduleAsBlock() {
      final now = DateTime.now();
      final from = task.date == dateKey(now)
          ? min(((now.hour * 60 + now.minute) ~/ 30 + 1) * 30, 1380)
          : 9 * 60;
      final start = store.suggestStart(task.date, from: from);
      showBlockEditor(
        context,
        date: task.date,
        start: start,
        end: min(start + 60, 1440),
        title: task.title,
        goalId: task.goalId,
      );
    }

    void delete() {
      final messenger = ScaffoldMessenger.of(context);
      final removed = store.deleteTask(task.id);
      if (removed != null) {
        showUndoSnackBar(messenger, 'Task deleted', () => store.saveTask(removed));
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showTaskEditor(context, task),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(value: task.done, onChanged: (_) => store.toggleTask(task.id)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      decoration: task.done ? TextDecoration.lineThrough : null,
                      color: task.done ? scheme.onSurfaceVariant : scheme.onSurface,
                    ),
                  ),
                  if (goal != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          ColorDot(goal!.color, size: 7),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              goal!.title,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: task.important ? 'Remove priority' : 'Mark as priority',
              visualDensity: VisualDensity.compact,
              onPressed: () => store.saveTask(task.copyWith(important: !task.important)),
              icon: Icon(
                task.important ? Icons.star_rounded : Icons.star_outline_rounded,
                color: task.important ? Colors.amber.shade600 : scheme.outline,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_vert, size: 20, color: scheme.onSurfaceVariant),
              onSelected: (value) {
                switch (value) {
                  case 'schedule':
                    scheduleAsBlock();
                  case 'tomorrow':
                    store.moveTasks([task.id], dateKey(addDays(parseDateKey(task.date), 1)));
                  case 'edit':
                    showTaskEditor(context, task);
                  case 'delete':
                    delete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'schedule',
                  child: ListTile(
                    leading: Icon(Icons.view_timeline_outlined),
                    title: Text('Schedule as time block'),
                  ),
                ),
                PopupMenuItem(
                  value: 'tomorrow',
                  child: ListTile(leading: Icon(Icons.redo), title: Text('Move to next day')),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- habits

class HabitsDayPanel extends StatelessWidget {
  const HabitsDayPanel({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final key = dateKey(date);
    final now = today();
    final isFuture = date.isAfter(now);
    final habits = store.habits.where((h) => h.isScheduledOn(date)).toList();
    final done = habits.where((h) => h.doneDates.contains(key)).length;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return SectionCard(
      icon: Icons.repeat,
      title: 'Habits',
      trailing: habits.isEmpty
          ? null
          : Text(
              '$done/${habits.length}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      child: store.habits.isEmpty
          ? Text('Create habits in the Habits tab and check them off here each day.', style: muted)
          : habits.isEmpty
          ? Text('No habits scheduled on this day.', style: muted)
          : Column(
              children: [
                for (final h in habits)
                  _HabitCheckRow(
                    habit: h,
                    done: h.doneDates.contains(key),
                    streak: h.currentStreak(now),
                    onToggle: isFuture ? null : () => store.toggleHabit(h.id, key),
                  ),
              ],
            ),
    );
  }
}

class _HabitCheckRow extends StatelessWidget {
  const _HabitCheckRow({
    required this.habit,
    required this.done,
    required this.streak,
    required this.onToggle,
  });

  final Habit habit;
  final bool done;
  final int streak;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(habit.color);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: done ? color : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: done ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(habit.name, style: theme.textTheme.bodyMedium)),
            if (streak > 0) ...[
              Icon(Icons.local_fire_department, size: 18, color: Colors.deepOrange.shade400),
              const SizedBox(width: 2),
              Text('$streak', style: theme.textTheme.labelLarge),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ notes

class NotesPanel extends StatefulWidget {
  const NotesPanel({super.key, required this.date});

  final DateTime date;

  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _loadedKey;

  static const _prompts = ['Wins today:', 'Could be better:', 'Grateful for:', 'Tomorrow:'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFromStore();
  }

  @override
  void didUpdateWidget(NotesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromStore();
  }

  /// Loads the note only when the day changes, so typing isn't disturbed.
  void _syncFromStore() {
    final key = dateKey(widget.date);
    if (key == _loadedKey) return;
    _loadedKey = key;
    _controller.text = PlannerScope.read(context).noteFor(key);
  }

  void _insertPrompt(String prompt) {
    final text = _controller.text;
    final separator = text.isEmpty || text.endsWith('\n') ? '' : '\n';
    _controller.value = TextEditingValue(
      text: '$text$separator$prompt ',
      selection: TextSelection.collapsed(
        offset: text.length + separator.length + prompt.length + 1,
      ),
    );
    PlannerScope.read(context).setNote(_loadedKey!, _controller.text);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      icon: Icons.edit_note,
      title: 'Notes & reflection',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focus,
            minLines: 5,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Plans, ideas, how the day went…',
              alignLabelWithHint: true,
            ),
            onChanged: (text) => PlannerScope.read(context).setNote(_loadedKey!, text),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in _prompts)
                ActionChip(
                  label: Text(p),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _insertPrompt(p),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
