import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/planner_scope.dart';
import '../util/dates.dart';
import '../widgets/common.dart';

/// Month overview: what's scheduled where, plus goal deadlines.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.onOpenDay});

  final ValueChanged<DateTime> onOpenDay;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _MonthData {
  final blocks = <String, List<TimeBlock>>{};
  final tasks = <String, List<Task>>{};
  final deadlines = <String, List<Goal>>{};
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _month = DateTime(today().year, today().month);

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final gridStart = startOfWeek(_month);
    final days = List.generate(42, (i) => addDays(gridStart, i));
    final from = dateKey(days.first);
    final to = dateKey(days.last);
    bool inRange(String k) => k.compareTo(from) >= 0 && k.compareTo(to) <= 0;

    final data = _MonthData();
    for (final b in store.blocks) {
      if (inRange(b.date)) data.blocks.putIfAbsent(b.date, () => []).add(b);
    }
    for (final list in data.blocks.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    for (final t in store.tasks) {
      if (inRange(t.date)) data.tasks.putIfAbsent(t.date, () => []).add(t);
    }
    for (final g in store.goals) {
      final due = g.dueDate;
      if (due != null && inRange(due)) data.deadlines.putIfAbsent(due, () => []).add(g);
    }

    final header = PageHeader(
      title: DateFormat.yMMMM().format(_month),
      subtitle: 'Open any day to plan it in detail.',
      actions: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () => _shift(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        OutlinedButton(
          onPressed: () => setState(() => _month = DateTime(today().year, today().month)),
          child: const Text('This month'),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: () => _shift(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = _MonthGrid(
          month: _month,
          days: days,
          data: data,
          hasNote: store.hasNote,
          onOpenDay: widget.onOpenDay,
        );
        final summary = _MonthSummary(month: _month, onOpenDay: widget.onOpenDay);

        if (constraints.maxWidth >= 1100) {
          return Column(
            children: [
              header,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: grid),
                      const SizedBox(width: 16),
                      SizedBox(width: 320, child: ListView(children: [summary])),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        final cell = ((constraints.maxWidth - 24) / 7).clamp(48.0, 140.0);
        return Column(
          children: [
            header,
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  SizedBox(height: 28 + 6 * (cell * 1.15), child: grid),
                  const SizedBox(height: 16),
                  summary,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.days,
    required this.data,
    required this.hasNote,
    required this.onOpenDay,
  });

  final DateTime month;
  final List<DateTime> days;
  final _MonthData data;
  final bool Function(String) hasNote;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      DateFormat.E().format(days[i]),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              for (var w = 0; w < 6; w++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var d = 0; d < 7; d++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: _DayCell(
                              date: days[w * 7 + d],
                              inMonth: days[w * 7 + d].month == month.month,
                              blocks: data.blocks[dateKey(days[w * 7 + d])] ?? const [],
                              tasks: data.tasks[dateKey(days[w * 7 + d])] ?? const [],
                              deadlines: data.deadlines[dateKey(days[w * 7 + d])] ?? const [],
                              hasNote: hasNote(dateKey(days[w * 7 + d])),
                              onTap: () => onOpenDay(days[w * 7 + d]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.blocks,
    required this.tasks,
    required this.deadlines,
    required this.hasNote,
    required this.onTap,
  });

  final DateTime date;
  final bool inMonth;
  final List<TimeBlock> blocks;
  final List<Task> tasks;
  final List<Goal> deadlines;
  final bool hasNote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isToday = isSameDay(date, today());
    final doneTasks = tasks.where((t) => t.done).length;
    final dim = !inMonth;

    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isToday ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.7),
            width: isToday ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: LayoutBuilder(
              builder: (context, c) {
                final showTitles = c.maxWidth >= 84 && c.maxHeight >= 64;
                final roomy = c.maxWidth >= 70;
                final reserved = 24 + (tasks.isNotEmpty ? 16 : 0);
                final lines = ((c.maxHeight - reserved) / 19).floor().clamp(0, 6);
                final shown = blocks.length > lines ? (lines - 1).clamp(0, 6) : blocks.length;

                return Stack(
                  children: [
                    ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isToday ? scheme.primary : null,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${date.day}',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: isToday ? scheme.onPrimary : scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (showTitles) ...[
                              for (final b in blocks.take(shown)) _MiniBlock(block: b),
                              if (blocks.length > shown)
                                Text(
                                  '+${blocks.length - shown} more',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ] else if (blocks.isNotEmpty || tasks.isNotEmpty)
                              // Small cells: dots for blocks plus a task marker, inline.
                              Wrap(
                                spacing: 3,
                                runSpacing: 3,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  for (final b in blocks.take(4)) ColorDot(b.color, size: 6),
                                  if (tasks.isNotEmpty)
                                    Icon(
                                      doneTasks == tasks.length
                                          ? Icons.task_alt
                                          : Icons.radio_button_unchecked,
                                      size: 9,
                                      color: doneTasks == tasks.length
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Note / deadline markers overlay the top-right corner.
                    Positioned(
                      top: 2,
                      right: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasNote && roomy)
                            Icon(Icons.notes, size: 13, color: scheme.onSurfaceVariant),
                          for (final g in deadlines.take(roomy ? 2 : 1))
                            Tooltip(
                              message: '${g.title} is due',
                              child: Icon(
                                g.completed ? Icons.emoji_events : Icons.flag,
                                size: 14,
                                color: Color(g.color),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (tasks.isNotEmpty && showTitles)
                      Positioned(
                        left: 2,
                        right: 0,
                        bottom: 0,
                        child: MetaLabel(
                          icon: doneTasks == tasks.length
                              ? Icons.task_alt
                              : Icons.radio_button_unchecked,
                          text: '$doneTasks/${tasks.length}',
                          color: doneTasks == tasks.length ? scheme.primary : null,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniBlock extends StatelessWidget {
  const _MiniBlock({required this.block});

  final TimeBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(block.color);
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: theme.brightness == Brightness.dark ? 0.32 : 0.16),
        border: Border(left: BorderSide(color: color, width: 3)),
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        block.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          decoration: block.done ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.month, required this.onOpenDay});

  final DateTime month;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final prefix = dateKey(month).substring(0, 7); // yyyy-MM
    final minutes = store.blocks
        .where((b) => b.date.startsWith(prefix))
        .fold(0, (sum, b) => sum + b.duration);
    final tasks = store.tasks.where((t) => t.date.startsWith(prefix));
    final doneTasks = tasks.where((t) => t.done).length;
    final journaled = List.generate(
      endOfMonth(month).day,
      (i) => DateTime(month.year, month.month, i + 1),
    ).where((d) => store.hasNote(dateKey(d))).length;
    final deadlines = store.goals.where((g) => g.dueDate?.startsWith(prefix) ?? false).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    Widget stat(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          icon: Icons.insights,
          title: DateFormat.MMMM().format(month),
          child: Column(
            children: [
              stat(Icons.schedule, 'Time planned', formatDuration(minutes)),
              stat(Icons.task_alt, 'Tasks done', '$doneTasks / ${tasks.length}'),
              stat(Icons.edit_note, 'Days with notes', '$journaled'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          icon: Icons.flag_outlined,
          title: 'Goal deadlines',
          child: deadlines.isEmpty
              ? Text(
                  'No goals are due this month.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Column(
                  children: [
                    for (final g in deadlines)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          g.completed ? Icons.emoji_events : Icons.flag,
                          color: Color(g.color),
                        ),
                        title: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          g.completed
                              ? 'Achieved'
                              : '${DateFormat.MMMd().format(parseDateKey(g.dueDate!))} · ${(g.progress * 100).round()}% done',
                        ),
                        onTap: () => onOpenDay(parseDateKey(g.dueDate!)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
