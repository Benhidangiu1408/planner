import 'dart:math';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/planner_scope.dart';
import '../../data/planner_store.dart';
import '../../util/dates.dart';
import '../../widgets/common.dart';
import 'goal_editor.dart';

enum _GoalsView { board, tree }

/// Long-range planning: goals grouped by horizon, from this week out to
/// the long term, each broken into milestones and sub-goals.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  bool _achieved = false;
  _GoalsView _view = _GoalsView.board;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final goals = store.goals.where((g) => g.completed == _achieved).toList()..sort(_byDueDate);

    final Widget body;
    if (goals.isEmpty && (_achieved || _view == _GoalsView.tree)) {
      body = _achieved
          ? const EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'Nothing here yet',
              message: 'Goals you mark as achieved will be collected here.',
            )
          : EmptyState(
              icon: Icons.account_tree_outlined,
              title: 'No goals yet',
              message: 'Start with a long-term or yearly goal, then break it down.',
              action: FilledButton(
                onPressed: () => showGoalEditor(context, horizon: Horizon.year),
                child: const Text('Create a goal'),
              ),
            );
    } else if (_view == _GoalsView.tree) {
      body = _GoalTree(goals: goals);
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          for (final h in Horizon.values)
            if (!_achieved || goals.any((g) => g.horizon == h))
              _HorizonSection(
                horizon: h,
                goals: goals.where((g) => g.horizon == h).toList(),
                canAdd: !_achieved,
              ),
        ],
      );
    }

    return Column(
      children: [
        PageHeader(
          title: 'Goals',
          subtitle: 'Think big, then break it down into sub-goals, milestones and daily blocks.',
          actions: [
            SegmentedButton<_GoalsView>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _GoalsView.board,
                  icon: Icon(Icons.view_agenda_outlined),
                  tooltip: 'By horizon',
                ),
                ButtonSegment(
                  value: _GoalsView.tree,
                  icon: Icon(Icons.account_tree_outlined),
                  tooltip: 'As a tree of sub-goals',
                ),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Active')),
                ButtonSegment(value: true, label: Text('Achieved')),
              ],
              selected: {_achieved},
              onSelectionChanged: (s) => setState(() => _achieved = s.first),
            ),
            FilledButton.icon(
              onPressed: () => showGoalEditor(context),
              icon: const Icon(Icons.add),
              label: const Text('New goal'),
            ),
          ],
        ),
        Expanded(child: body),
      ],
    );
  }
}

int _byDueDate(Goal a, Goal b) {
  final ad = a.dueDate ?? '9999';
  final bd = b.dueDate ?? '9999';
  return ad != bd ? ad.compareTo(bd) : a.createdAt.compareTo(b.createdAt);
}

IconData horizonIcon(Horizon h) => switch (h) {
  Horizon.week => Icons.view_week_outlined,
  Horizon.month => Icons.calendar_view_month_outlined,
  Horizon.quarter => Icons.date_range_outlined,
  Horizon.year => Icons.event_available_outlined,
  Horizon.longTerm => Icons.landscape_outlined,
};

String horizonPeriod(Horizon h) {
  final now = today();
  return switch (h) {
    Horizon.week =>
      '${DateFormat.MMMd().format(startOfWeek(now))} – ${DateFormat.MMMd().format(endOfWeek(now))}',
    Horizon.month => DateFormat.yMMMM().format(now),
    Horizon.quarter =>
      'Q${quarterOf(now)} · ${DateFormat.MMM().format(startOfQuarter(now))} – ${DateFormat.yMMM().format(endOfQuarter(now))}',
    Horizon.year => '${now.year}',
    Horizon.longTerm => 'Beyond ${now.year}',
  };
}

void _addSubGoal(BuildContext context, Goal parent) => showGoalEditor(
  context,
  parentId: parent.id,
  horizon: parent.horizon == Horizon.week ? Horizon.week : parent.horizon.shorter,
);

class _HorizonSection extends StatelessWidget {
  const _HorizonSection({required this.horizon, required this.goals, required this.canAdd});

  final Horizon horizon;
  final List<Goal> goals;
  final bool canAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(horizonIcon(horizon), size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                horizon.label,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  horizonPeriod(horizon),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (canAdd)
                TextButton.icon(
                  onPressed: () => showGoalEditor(context, horizon: horizon),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (goals.isEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: canAdd ? () => showGoalEditor(context, horizon: horizon) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Text(
                  horizon.prompt,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final columns = max(1, (c.maxWidth / 340).floor());
                final width = (c.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final g in goals)
                      SizedBox(
                        width: width,
                        child: GoalCard(goal: g),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(goal.color);
    final due = goal.dueDate == null ? null : parseDateKey(goal.dueDate!);
    final overdue = due != null && !goal.completed && daysBetween(today(), due) < 0;
    final planned = store.plannedMinutesFor(goal.id);
    final focused = store.focusMinutesForGoal(goal.id);
    final taskStats = store.taskStatsFor(goal.id);
    final doneMilestones = goal.milestones.where((m) => m.done).length;
    final children = store.childrenOf(goal.id);
    final parent = store.goalById(goal.parentId);
    final progress = store.progressOf(goal);
    final next = goal.nextMilestone;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showGoalEditor(context, goal: goal),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal.title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (goal.completed) Icon(Icons.emoji_events, color: color),
                  _GoalMenu(goal: goal),
                ],
              ),
              if (parent != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 2),
                  child: MetaLabel(
                    icon: Icons.subdirectory_arrow_right,
                    text: 'Part of ${parent.title}',
                  ),
                ),
              if (goal.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 12),
                  child: Text(
                    goal.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        color: color,
                        backgroundColor: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${(progress * 100).round()}%', style: theme.textTheme.labelLarge),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  if (due != null)
                    MetaLabel(
                      icon: Icons.event,
                      text: goal.completed ? DateFormat.yMMMd().format(due) : dueLabel(due),
                      color: overdue ? scheme.error : null,
                    ),
                  if (goal.milestones.isNotEmpty)
                    MetaLabel(
                      icon: Icons.checklist,
                      text: '$doneMilestones/${goal.milestones.length}',
                    ),
                  if (children.isNotEmpty)
                    MetaLabel(
                      icon: Icons.account_tree_outlined,
                      text: '${children.length} sub-goal${children.length == 1 ? '' : 's'}',
                    ),
                  if (planned > 0) MetaLabel(icon: Icons.schedule, text: formatDuration(planned)),
                  if (focused > 0)
                    MetaLabel(
                      icon: Icons.timer_outlined,
                      text: '${formatDuration(focused)} focused',
                    ),
                  if (taskStats.total > 0)
                    MetaLabel(
                      icon: Icons.task_alt,
                      text: '${taskStats.done}/${taskStats.total} tasks',
                    ),
                ],
              ),
              if (next != null && !goal.completed) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Material(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => store.toggleMilestone(goal.id, next.id),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
                        child: Row(
                          children: [
                            Icon(Icons.check_box_outline_blank, size: 18, color: color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Next: ',
                                      style: TextStyle(color: scheme.onSurfaceVariant),
                                    ),
                                    TextSpan(text: next.title),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalMenu extends StatelessWidget {
  const _GoalMenu({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.read(context);
    return PopupMenuButton<String>(
      tooltip: 'More',
      iconSize: 20,
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            showGoalEditor(context, goal: goal);
          case 'sub':
            _addSubGoal(context, goal);
          case 'achieved':
            store.saveGoal(goal.copyWith(completed: !goal.completed));
          case 'delete':
            final ok = await confirmAction(
              context,
              title: 'Delete goal?',
              message: 'Linked tasks, time blocks and sub-goals are kept but will no longer point to this goal.',
            );
            if (ok) store.deleteGoal(goal.id);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit')),
        ),
        if (goal.horizon != Horizon.week)
          const PopupMenuItem(
            value: 'sub',
            child: ListTile(
              leading: Icon(Icons.account_tree_outlined),
              title: Text('Add sub-goal'),
            ),
          ),
        PopupMenuItem(
          value: 'achieved',
          child: ListTile(
            leading: Icon(goal.completed ? Icons.undo : Icons.emoji_events_outlined),
            title: Text(goal.completed ? 'Mark as active' : 'Mark as achieved'),
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- tree

/// Goals as an outline: long-term → year → quarter → month → week.
class _GoalTree extends StatelessWidget {
  const _GoalTree({required this.goals});

  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final ids = goals.map((g) => g.id).toSet();
    // Roots: no parent, or a parent that isn't in the current list.
    final roots = goals.where((g) => g.parentId == null || !ids.contains(g.parentId)).toList()
      ..sort((a, b) {
        final h = b.horizon.index.compareTo(a.horizon.index);
        return h != 0 ? h : _byDueDate(a, b);
      });
    final rows = <Widget>[];
    void visit(Goal g, int depth, Set<String> seen) {
      if (!seen.add(g.id)) return;
      rows.add(_TreeRow(goal: g, depth: depth, store: store));
      final kids = goals.where((c) => c.parentId == g.id).toList()..sort(_byDueDate);
      for (final k in kids) {
        visit(k, depth + 1, seen);
      }
    }

    final seen = <String>{};
    for (final r in roots) {
      visit(r, 0, seen);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: rows);
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({required this.goal, required this.depth, required this.store});

  final Goal goal;
  final int depth;
  final PlannerStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(goal.color);
    final progress = store.progressOf(goal);
    final due = goal.dueDate == null ? null : parseDateKey(goal.dueDate!);
    final indent = min(depth, 6) * 28.0;

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showGoalEditor(context, goal: goal),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                if (depth > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.subdirectory_arrow_right, size: 18, color: scheme.outline),
                  ),
                Icon(horizonIcon(goal.horizon), size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.title, style: theme.textTheme.titleSmall),
                      Text(
                        [
                          goal.horizon.label,
                          if (due != null)
                            goal.completed ? DateFormat.yMMMd().format(due) : dueLabel(due),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${(progress * 100).round()}%',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ),
                if (goal.horizon != Horizon.week && !goal.completed)
                  IconButton(
                    tooltip: 'Add sub-goal',
                    onPressed: () => _addSubGoal(context, goal),
                    icon: const Icon(Icons.add, size: 20),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
