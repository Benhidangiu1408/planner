import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/planner_scope.dart';
import '../util/dates.dart';
import '../util/palette.dart';
import 'common.dart';

/// Makes a task draggable onto a timeline (to schedule it) or another day.
///
/// With [longPress] the drag starts after a long press, which keeps vertical
/// lists scrollable on touch screens. Otherwise only horizontal touch drags
/// start it; mice can drag in any direction.
class TaskDraggable extends StatelessWidget {
  const TaskDraggable({super.key, required this.task, required this.child, this.longPress = false});

  final Task task;
  final Widget child;
  final bool longPress;

  @override
  Widget build(BuildContext context) {
    final feedback = _TaskDragFeedback(task: task);
    final dimmed = Opacity(opacity: 0.4, child: child);
    if (longPress) {
      return LongPressDraggable<Task>(
        data: task,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: feedback,
        childWhenDragging: dimmed,
        child: child,
      );
    }
    return Draggable<Task>(
      data: task,
      affinity: Axis.horizontal,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging: dimmed,
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: child),
    );
  }
}

class _TaskDragFeedback extends StatelessWidget {
  const _TaskDragFeedback({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Transform.translate(
      offset: const Offset(8, -16),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.task_alt, size: 16, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Turns a task into a one-hour block at [start] on [date], moving the task
/// to that day if needed. Offers undo.
void scheduleTask(BuildContext context, Task task, String date, int start) {
  final store = PlannerScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final goal = store.goalById(task.goalId);
  final from = min(start, 1440 - 15);
  final block = store.saveBlock(
    TimeBlock(
      id: newId(),
      date: date,
      start: from,
      end: min(from + 60, 1440),
      title: task.title,
      color: goal?.color ?? plannerColors.first,
      goalId: task.goalId,
    ),
  );
  final originalDate = task.date;
  if (originalDate != date) store.moveTasks([task.id], date);
  showUndoSnackBar(
    messenger,
    'Scheduled "${task.title}" at ${formatClock(from, use24h: store.settings.use24h)}',
    () {
      store.deleteBlock(block.id);
      if (originalDate != date) store.moveTasks([task.id], originalDate);
    },
  );
}
