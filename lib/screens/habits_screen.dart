import 'dart:math';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/planner_scope.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/editors.dart';

class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final habits = PlannerScope.of(context).habits;
    return Column(
      children: [
        PageHeader(
          title: 'Habits',
          subtitle: 'Small, repeated actions that move your goals forward.',
          actions: [
            FilledButton.icon(
              onPressed: () => showHabitEditor(context),
              icon: const Icon(Icons.add),
              label: const Text('New habit'),
            ),
          ],
        ),
        Expanded(
          child: habits.isEmpty
              ? EmptyState(
                  icon: Icons.repeat,
                  title: 'No habits yet',
                  message: 'Start small: read 10 pages, a 20-minute walk, no phone after 10pm.',
                  action: FilledButton(
                    onPressed: () => showHabitEditor(context),
                    child: const Text('Create a habit'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  itemCount: habits.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _HabitCard(habit: habits[i]),
                ),
        ),
      ],
    );
  }
}

String _scheduleLabel(Habit h) {
  if (h.weekdays.isEmpty) return 'Every day';
  if (h.weekdays.length == 5 && !h.weekdays.contains(6) && !h.weekdays.contains(7)) {
    return 'Weekdays';
  }
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return h.weekdays.map((d) => names[d - 1]).join(', ');
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(habit.color);
    final now = today();
    final streak = habit.currentStreak(now);
    final best = habit.bestStreak(now);
    final rate = habit.completionRate(now);

    final stats = Wrap(
      spacing: 20,
      runSpacing: 8,
      children: [
        _Stat(
          icon: Icons.local_fire_department,
          iconColor: Colors.deepOrange.shade400,
          value: '$streak',
          label: 'streak',
        ),
        _Stat(icon: Icons.emoji_events_outlined, value: '$best', label: 'best'),
        _Stat(icon: Icons.percent, value: '${(rate * 100).round()}%', label: 'last 30 days'),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 760;
            final title = Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.repeat, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.name,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _scheduleLabel(habit),
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (wide) stats,
                IconButton(
                  tooltip: 'Edit habit',
                  onPressed: () => showHabitEditor(context, habit: habit),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            );
            final heatWeeks = wide ? 20 : max(6, ((c.maxWidth + 3) / 14).floor());
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                if (!wide) ...[const SizedBox(height: 12), stats],
                const SizedBox(height: 16),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _LastSevenDays(habit: habit),
                      const Spacer(),
                      _Heatmap(habit: habit, weeks: heatWeeks),
                    ],
                  )
                else ...[
                  _LastSevenDays(habit: habit),
                  const SizedBox(height: 16),
                  _Heatmap(habit: habit, weeks: heatWeeks),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label, this.iconColor});

  final IconData icon;
  final String value;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: iconColor ?? theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Tappable check circles for the last seven days.
class _LastSevenDays extends StatelessWidget {
  const _LastSevenDays({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.read(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(habit.color);
    final now = today();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 6; i >= 0; i--)
          Builder(
            builder: (context) {
              final d = addDays(now, -i);
              final done = habit.isDoneOn(d);
              final scheduled = habit.isScheduledOn(d);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  children: [
                    Text(
                      i == 0 ? 'Today' : DateFormat.E().format(d),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: i == 0 ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: i == 0 ? FontWeight.w700 : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Tooltip(
                      message: DateFormat.MMMEd().format(d),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => store.toggleHabit(habit.id, dateKey(d)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: done ? color : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheduled ? color : scheme.outlineVariant,
                              width: scheduled ? 2 : 1,
                            ),
                          ),
                          child: done
                              ? const Icon(Icons.check, size: 18, color: Colors.white)
                              : Text(
                                  '${d.day}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: scheduled ? scheme.onSurface : scheme.outline,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// GitHub-style grid: one column per week, Monday at the top.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.habit, required this.weeks});

  final Habit habit;
  final int weeks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color(habit.color);
    final now = today();
    final created = parseDateKey(habit.createdOn);
    final first = addDays(startOfWeek(now), -(weeks - 1) * 7);
    const cell = 11.0;
    const gap = 3.0;

    Color colorFor(DateTime d) {
      if (d.isAfter(now)) return Colors.transparent;
      if (habit.isDoneOn(d)) return color;
      if (d.isBefore(created) || !habit.isScheduledOn(d)) {
        return scheme.surfaceContainerHigh.withValues(alpha: 0.5);
      }
      return scheme.surfaceContainerHighest;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var w = 0; w < weeks; w++)
          Padding(
            padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : gap),
            child: Column(
              children: [
                for (var d = 0; d < 7; d++)
                  Container(
                    width: cell,
                    height: cell,
                    margin: EdgeInsets.only(bottom: d == 6 ? 0 : gap),
                    decoration: BoxDecoration(
                      color: colorFor(addDays(first, w * 7 + d)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
