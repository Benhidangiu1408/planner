import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/planner_scope.dart';
import '../../util/dates.dart';
import '../../widgets/week_focus.dart';
import 'panels.dart';
import 'timeline.dart';

/// Short-range planning: a time-blocked schedule plus the day's tasks,
/// habits and a reflection note.
class DayScreen extends StatelessWidget {
  const DayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final date = PlannerScope.of(context).selectedDate;
    return LayoutBuilder(
      builder: (context, constraints) {
        final header = _DayHeader(date: date, compact: constraints.maxWidth < 600);
        if (constraints.maxWidth >= 1000) {
          return Column(
            children: [
              header,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: DayTimeline(date: date)),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: constraints.maxWidth >= 1300 ? 420 : 360,
                        child: ListView(
                          children: [
                            TasksPanel(date: date, draggable: true),
                            const SizedBox(height: 16),
                            HabitsDayPanel(date: date),
                            const SizedBox(height: 16),
                            NotesPanel(date: date),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              header,
              const TabBar(
                tabs: [
                  Tab(text: 'Schedule'),
                  Tab(text: 'Tasks & habits'),
                  Tab(text: 'Notes'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: DayTimeline(date: date),
                    ),
                    ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        TasksPanel(date: date),
                        const SizedBox(height: 12),
                        HabitsDayPanel(date: date),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.all(12),
                      children: [NotesPanel(date: date)],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.compact});

  final DateTime date;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final key = dateKey(date);
    final relative = relativeDayLabel(date);
    final planned = store.plannedMinutesOn(key);
    final tasks = store.tasksOn(key);
    final doneTasks = tasks.where((t) => t.done).length;

    Future<void> pickDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) store.selectDate(picked);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Previous day',
                    onPressed: () => store.selectDate(addDays(date, -1)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next day',
                    onPressed: () => store.selectDate(addDays(date, 1)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: InkWell(
                      onTap: pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat.EEEE().format(date),
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (compact
                                          ? theme.textTheme.titleLarge
                                          : theme.textTheme.headlineSmall)
                                      ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              [
                                (compact ? DateFormat.yMMMd() : DateFormat.yMMMMd()).format(date),
                                if (relative.isNotEmpty) relative,
                              ].join(' · '),
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatChip(icon: Icons.schedule, label: '${formatDuration(planned)} planned'),
                  _StatChip(icon: Icons.task_alt, label: '$doneTasks/${tasks.length} tasks'),
                  if (relative != 'Today')
                    FilledButton.tonalIcon(
                      onPressed: () => store.selectDate(today()),
                      icon: const Icon(Icons.today, size: 18),
                      label: const Text('Today'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _WeekStrip(date: date),
          const SizedBox(height: 4),
          WeekFocusStrip(day: date),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: scheme.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}

/// Monday–Sunday strip for quick navigation within the week.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = startOfWeek(date);
    final now = today();

    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final d = addDays(start, i);
              final key = dateKey(d);
              final selected = isSameDay(d, date);
              final isToday = isSameDay(d, now);
              final busy = store.plannedMinutesOn(key) > 0 || store.tasksOn(key).isNotEmpty;
              final bg = selected
                  ? scheme.primary
                  : isToday
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh;
              final fg = selected
                  ? scheme.onPrimary
                  : isToday
                  ? scheme.onPrimaryContainer
                  : scheme.onSurface;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: selected ? null : bg,
                      // The selected day blends the main color into the second one.
                      gradient: selected
                          ? LinearGradient(
                              colors: [scheme.primary, scheme.secondary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => store.selectDate(d),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Text(
                              DateFormat.E().format(d),
                              style: theme.textTheme.labelSmall?.copyWith(color: fg),
                            ),
                            Text(
                              '${d.day}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: busy ? fg.withValues(alpha: 0.8) : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
