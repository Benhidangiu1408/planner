import 'dart:math';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/planner_scope.dart';
import '../data/planner_store.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/week_focus.dart';

/// Looks back at a week (time per goal and day, planned vs focused, habits)
/// and sets up the next one.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  DateTime _weekStart = startOfWeek(today());
  final _wentWell = TextEditingController();
  final _improve = TextEditingController();
  final _intention = TextEditingController();
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  /// Fills the text fields when the week changes (not on every keystroke).
  void _load() {
    final key = dateKey(_weekStart);
    if (_loadedFor == key) return;
    _loadedFor = key;
    final store = PlannerScope.read(context);
    final plan = store.weekPlan(key);
    _wentWell.text = plan.wentWell;
    _improve.text = plan.improve;
    _intention.text = store.weekPlan(dateKey(addDays(_weekStart, 7))).intention;
  }

  void _shift(int weeks) {
    setState(() => _weekStart = addDays(_weekStart, 7 * weeks));
    _load();
  }

  @override
  void dispose() {
    _wentWell.dispose();
    _improve.dispose();
    _intention.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final data = _WeekData.compute(store, _weekStart);
    final isThisWeek = isSameDay(_weekStart, startOfWeek(today()));

    return Column(
      children: [
        PageHeader(
          title: 'Weekly review',
          subtitle: weekRangeLabel(_weekStart),
          actions: [
            IconButton(
              tooltip: 'Previous week',
              onPressed: () => _shift(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            OutlinedButton(
              onPressed: isThisWeek
                  ? null
                  : () {
                      setState(() => _weekStart = startOfWeek(today()));
                      _load();
                    },
              child: const Text('This week'),
            ),
            IconButton(
              tooltip: 'Next week',
              onPressed: () => _shift(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 1000;
              Widget pair(Widget a, Widget b) => wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: a),
                        const SizedBox(width: 16),
                        Expanded(child: b),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [a, const SizedBox(height: 16), b],
                    );

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _Overview(data: data),
                  const SizedBox(height: 16),
                  pair(_TimeByGoal(data: data), _TimeByDay(data: data)),
                  const SizedBox(height: 16),
                  pair(_HabitsThisWeek(data: data), _FocusGoalsCard(data: data)),
                  const SizedBox(height: 16),
                  pair(_reflection(context, store), _planNext(context, store, data)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _reflection(BuildContext context, PlannerStore store) {
    final key = dateKey(_weekStart);
    return SectionCard(
      icon: Icons.self_improvement,
      title: 'Reflect',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _wentWell,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What went well?',
              alignLabelWithHint: true,
            ),
            onChanged: (v) => store.saveWeekPlan(store.weekPlan(key).copyWith(wentWell: v)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _improve,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What would you do differently?',
              alignLabelWithHint: true,
            ),
            onChanged: (v) => store.saveWeekPlan(store.weekPlan(key).copyWith(improve: v)),
          ),
        ],
      ),
    );
  }

  Widget _planNext(BuildContext context, PlannerStore store, _WeekData data) {
    final theme = Theme.of(context);
    final next = addDays(_weekStart, 7);
    final nextKey = dateKey(next);
    final plan = store.weekPlan(nextKey);
    final goals = store.goals.where((g) => !g.completed).toList()
      ..sort((a, b) => a.horizon.index.compareTo(b.horizon.index));
    final selected = plan.focusGoalIds.toSet();
    final unfinished = data.unfinishedTasks;

    return SectionCard(
      icon: Icons.next_plan_outlined,
      title: 'Plan next week',
      trailing: Text(
        weekRangeLabel(next),
        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Focus on (up to $maxFocusGoals)', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (goals.isEmpty)
            Text('No active goals yet. Add some in Goals.', style: theme.textTheme.bodySmall)
          else
            FocusGoalChips(
              goals: goals,
              selected: selected,
              onToggle: (id) {
                final ids = {...selected};
                ids.contains(id) ? ids.remove(id) : ids.add(id);
                store.saveWeekPlan(store.weekPlan(nextKey).copyWith(focusGoalIds: ids.toList()));
              },
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _intention,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Intention for next week'),
            onChanged: (v) =>
                store.saveWeekPlan(store.weekPlan(nextKey).copyWith(intention: v.trim())),
          ),
          const SizedBox(height: 16),
          if (unfinished.isEmpty)
            MetaLabel(icon: Icons.task_alt, text: 'No unfinished tasks this week.')
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${unfinished.length} unfinished task${unfinished.length == 1 ? '' : 's'} this week',
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    store.moveTasks(unfinished.map((t) => t.id), nextKey);
                    showMessage(
                      context,
                      'Moved ${unfinished.length} to ${DateFormat.MMMEd().format(next)}.',
                    );
                  },
                  child: Text('Move to ${DateFormat.E().format(next)}'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Everything the review shows, computed once per build.
class _WeekData {
  _WeekData._();

  late List<DateTime> days;
  late List<int> plannedByDay;
  late List<int> focusedByDay;
  int blocksDone = 0;
  int blocksTotal = 0;
  int tasksDone = 0;
  int tasksTotal = 0;
  List<Task> unfinishedTasks = [];
  int notesDays = 0;

  /// (goal or null for unlinked, planned minutes, focused minutes)
  List<(Goal?, int, int)> byGoal = [];
  List<(Habit, List<_HabitDay>, int, int)> habits = [];
  List<(Goal, double, int, int)> focusGoals = [];

  int get planned => plannedByDay.fold(0, (a, b) => a + b);
  int get focused => focusedByDay.fold(0, (a, b) => a + b);

  static _WeekData compute(PlannerStore store, DateTime weekStart) {
    final d = _WeekData._();
    final now = today();
    d.days = [for (var i = 0; i < 7; i++) addDays(weekStart, i)];
    final keys = d.days.map(dateKey).toList();
    final from = keys.first;
    final to = keys.last;
    final blocks = store.blocksBetween(d.days.first, d.days.last);
    final sessions = store.sessionsBetween(from, to);

    d.plannedByDay = [
      for (final k in keys) (blocks[k] ?? const []).fold(0, (s, b) => s + b.duration),
    ];
    d.focusedByDay = [
      for (final k in keys) sessions.where((s) => s.date == k).fold(0, (s, x) => s + x.minutes),
    ];

    final plannedByGoal = <String?, int>{};
    for (final list in blocks.values) {
      for (final b in list) {
        d.blocksTotal++;
        if (b.done) d.blocksDone++;
        final goalId = store.goalById(b.goalId)?.id;
        plannedByGoal[goalId] = (plannedByGoal[goalId] ?? 0) + b.duration;
      }
    }
    final focusedByGoal = <String?, int>{};
    for (final s in sessions) {
      final goalId = store.goalById(s.goalId)?.id;
      focusedByGoal[goalId] = (focusedByGoal[goalId] ?? 0) + s.minutes;
    }
    d.byGoal =
        [
          for (final id in {...plannedByGoal.keys, ...focusedByGoal.keys})
            (store.goalById(id), plannedByGoal[id] ?? 0, focusedByGoal[id] ?? 0),
        ]..sort((a, b) {
          // Unlinked time last, otherwise biggest first.
          if ((a.$1 == null) != (b.$1 == null)) return a.$1 == null ? 1 : -1;
          return max(b.$2, b.$3).compareTo(max(a.$2, a.$3));
        });

    final weekTasks = store.tasks.where(
      (t) => t.date.compareTo(from) >= 0 && t.date.compareTo(to) <= 0,
    );
    d.tasksTotal = weekTasks.length;
    d.tasksDone = weekTasks.where((t) => t.done).length;
    d.unfinishedTasks = weekTasks.where((t) => !t.done).toList();
    d.notesDays = keys.where(store.hasNote).length;

    d.habits = [
      for (final h in store.habits)
        () {
          final stats = h.statsBetween(d.days.first, d.days.last, now);
          final perDay = [
            for (final day in d.days)
              day.isAfter(now)
                  ? _HabitDay.future
                  : h.isDoneOn(day)
                  ? _HabitDay.done
                  : h.isScheduledOn(day) && !day.isBefore(parseDateKey(h.createdOn))
                  ? _HabitDay.missed
                  : _HabitDay.off,
          ];
          return (h, perDay, stats.done, stats.scheduled);
        }(),
    ];

    d.focusGoals = [
      for (final g in store.focusGoalsFor(weekStart))
        (g, store.progressOf(g), plannedByGoal[g.id] ?? 0, focusedByGoal[g.id] ?? 0),
    ];
    return d;
  }
}

enum _HabitDay { done, missed, off, future }

// ---------------------------------------------------------------- overview

class _Overview extends StatelessWidget {
  const _Overview({required this.data});

  final _WeekData data;

  @override
  Widget build(BuildContext context) {
    final habitDone = data.habits.fold(0, (s, h) => s + h.$3);
    final habitScheduled = data.habits.fold(0, (s, h) => s + h.$4);
    String pct(int a, int b) => b == 0 ? '—' : '${(a / b * 100).round()}%';

    final tiles = [
      _StatTile(
        label: 'Planned',
        value: formatDuration(data.planned),
        detail: '${data.blocksDone}/${data.blocksTotal} blocks done',
      ),
      _StatTile(
        label: 'Focused',
        value: formatDuration(data.focused),
        detail: data.planned == 0
            ? 'with the focus timer'
            : '${pct(data.focused, data.planned)} of planned',
      ),
      _StatTile(
        label: 'Tasks done',
        value: '${data.tasksDone}/${data.tasksTotal}',
        detail: data.unfinishedTasks.isEmpty ? 'all clear' : '${data.unfinishedTasks.length} open',
      ),
      _StatTile(
        label: 'Habits',
        value: pct(habitDone, habitScheduled),
        detail: '$habitDone of $habitScheduled check-ins',
      ),
      _StatTile(label: 'Journal', value: '${data.notesDays}/7', detail: 'days with notes'),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 900 ? 5 : (c.maxWidth >= 560 ? 3 : 2);
        final width = (c.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.detail});

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge?.copyWith(color: muted)),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ charts

/// Legend swatch for the "planned" (tint) vs "focused" (solid) encoding.
class _Legend extends StatelessWidget {
  const _Legend({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    Widget swatch(Color c) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
    );
    return Wrap(
      spacing: 14,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch(color.withValues(alpha: 0.35)),
            const SizedBox(width: 6),
            Text('Planned', style: style),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch(color),
            const SizedBox(width: 6),
            Text('Focused', style: style),
          ],
        ),
      ],
    );
  }
}

/// A card that can flip between a chart and the same data as a table.
class _ChartCard extends StatefulWidget {
  const _ChartCard({
    required this.title,
    required this.icon,
    required this.chart,
    required this.columns,
    required this.rows,
    this.empty,
  });

  final String title;
  final IconData icon;
  final Widget chart;
  final List<String> columns;
  final List<List<String>> rows;

  /// Shown instead of the chart when there's nothing to plot.
  final String? empty;

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  bool _table = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      icon: widget.icon,
      title: widget.title,
      trailing: widget.empty != null
          ? null
          : IconButton(
              tooltip: _table ? 'Show chart' : 'Show as table',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _table = !_table),
              icon: Icon(_table ? Icons.bar_chart : Icons.table_rows_outlined, size: 20),
            ),
      child: widget.empty != null
          ? Text(
              widget.empty!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : _table
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 40,
                columns: [
                  for (var i = 0; i < widget.columns.length; i++)
                    DataColumn(label: Text(widget.columns[i]), numeric: i > 0),
                ],
                rows: [
                  for (final r in widget.rows)
                    DataRow(cells: [for (final c in r) DataCell(Text(c))]),
                ],
              ),
            )
          : widget.chart,
    );
  }
}

class _TimeByGoal extends StatelessWidget {
  const _TimeByGoal({required this.data});

  final _WeekData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = data.byGoal;
    final maxMinutes = rows.fold(1, (m, r) => max(m, max(r.$2, r.$3)));

    return _ChartCard(
      title: 'Time by goal',
      icon: Icons.flag_outlined,
      empty: rows.isEmpty ? 'No time blocks or focus sessions this week.' : null,
      columns: const ['Goal', 'Planned', 'Focused'],
      rows: [
        for (final (goal, planned, focused) in rows)
          [goal?.title ?? 'No goal', formatDuration(planned), formatDuration(focused)],
      ],
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Legend(color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          for (final (goal, planned, focused) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Tooltip(
                message:
                    '${goal?.title ?? 'No goal'}\nPlanned ${formatDuration(planned)} · focused ${formatDuration(focused)}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (goal != null) ColorDot(goal.color, size: 8),
                        if (goal != null) const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            goal?.title ?? 'No goal',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        Text(
                          '${formatDuration(planned)} · ${formatDuration(focused)} focused',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _HBar(
                      fraction: planned / maxMinutes,
                      color: (goal == null ? scheme.outline : Color(goal.color)).withValues(
                        alpha: 0.35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _HBar(
                      fraction: focused / maxMinutes,
                      color: goal == null ? scheme.outline : Color(goal.color),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Thin horizontal bar: square at the baseline, 4px rounded at the data end.
class _HBar extends StatelessWidget {
  const _HBar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = fraction <= 0 ? 0.0 : max(3.0, c.maxWidth * fraction.clamp(0, 1));
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: w,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
          ),
        ),
      );
    },
  );
}

class _TimeByDay extends StatelessWidget {
  const _TimeByDay({required this.data});

  final _WeekData data;

  static const double chartHeight = 160;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final peak = [...data.plannedByDay, ...data.focusedByDay].fold(0, max);
    // Round the axis up to whole hours.
    final axisHours = max(1, (peak / 60).ceil());
    final axisMinutes = axisHours * 60;
    final gridStep = axisHours <= 4 ? 1 : (axisHours <= 8 ? 2 : 4);
    final busiest = data.plannedByDay.indexOf(data.plannedByDay.fold(0, max));
    final muted = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    return _ChartCard(
      title: 'Time by day',
      icon: Icons.bar_chart,
      empty: peak == 0 ? 'Nothing planned this week yet.' : null,
      columns: const ['Day', 'Planned', 'Focused'],
      rows: [
        for (var i = 0; i < 7; i++)
          [
            DateFormat.E().format(data.days[i]),
            formatDuration(data.plannedByDay[i]),
            formatDuration(data.focusedByDay[i]),
          ],
      ],
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Legend(color: scheme.primary),
          const SizedBox(height: 16),
          SizedBox(
            height: chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Y axis labels.
                SizedBox(
                  width: 30,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var h = 0; h <= axisHours; h += gridStep)
                        Positioned(
                          right: 6,
                          bottom: h / axisHours * chartHeight - 7,
                          child: Text('${h}h', style: muted),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      // Recessive gridlines.
                      for (var h = 0; h <= axisHours; h += gridStep)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: h / axisHours * chartHeight,
                          height: 1,
                          child: ColoredBox(
                            color: h == 0
                                ? scheme.outline
                                : scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: Tooltip(
                                message:
                                    '${DateFormat.MMMEd().format(data.days[i])}\n'
                                    'Planned ${formatDuration(data.plannedByDay[i])} · '
                                    'focused ${formatDuration(data.focusedByDay[i])}',
                                child: Container(
                                  // Hit target taller than the marks.
                                  color: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (i == busiest && data.plannedByDay[i] > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            formatDuration(data.plannedByDay[i]),
                                            style: muted,
                                          ),
                                        ),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          _VBar(
                                            height:
                                                data.plannedByDay[i] /
                                                axisMinutes *
                                                (chartHeight - 18),
                                            color: scheme.primary.withValues(alpha: 0.35),
                                          ),
                                          const SizedBox(width: 2),
                                          _VBar(
                                            height:
                                                data.focusedByDay[i] /
                                                axisMinutes *
                                                (chartHeight - 18),
                                            color: scheme.primary,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 30),
              for (final d in data.days)
                Expanded(
                  child: Text(
                    DateFormat.E().format(d),
                    textAlign: TextAlign.center,
                    style: muted?.copyWith(
                      fontWeight: isSameDay(d, today()) ? FontWeight.w700 : null,
                      color: isSameDay(d, today()) ? scheme.primary : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Thin vertical bar: square at the baseline, 4px rounded at the top.
class _VBar extends StatelessWidget {
  const _VBar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Flexible(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 14),
      child: Container(
        height: height <= 0 ? 0 : max(2.0, height),
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ),
    ),
  );
}

// -------------------------------------------------------- habits & focus

class _HabitsThisWeek extends StatelessWidget {
  const _HabitsThisWeek({required this.data});

  final _WeekData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SectionCard(
      icon: Icons.repeat,
      title: 'Habits',
      child: data.habits.isEmpty
          ? Text(
              'No habits yet.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          : Column(
              children: [
                Row(
                  children: [
                    const Spacer(),
                    for (final d in data.days)
                      SizedBox(
                        width: 22,
                        child: Text(
                          DateFormat('EEEEE').format(d),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(width: 52),
                  ],
                ),
                const SizedBox(height: 4),
                for (final (habit, days, done, scheduled) in data.habits)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            habit.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        for (final day in days)
                          Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: switch (day) {
                                _HabitDay.done => Color(habit.color),
                                _HabitDay.missed => scheme.surfaceContainerHighest,
                                _ => Colors.transparent,
                              },
                              border: day == _HabitDay.off
                                  ? Border.all(color: scheme.outlineVariant)
                                  : null,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: day == _HabitDay.done
                                ? const Icon(Icons.check, size: 12, color: Colors.white)
                                : null,
                          ),
                        SizedBox(
                          width: 52,
                          child: Text(
                            '$done/$scheduled',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _FocusGoalsCard extends StatelessWidget {
  const _FocusGoalsCard({required this.data});

  final _WeekData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SectionCard(
      icon: Icons.center_focus_strong_outlined,
      title: "This week's focus",
      child: data.focusGoals.isEmpty
          ? Text(
              'No focus goals were set for this week. Pick some for next week below.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          : Column(
              children: [
                for (final (goal, progress, planned, focused) in data.focusGoals)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ColorDot(goal.color),
                            const SizedBox(width: 8),
                            Expanded(child: Text(goal.title, style: theme.textTheme.labelLarge)),
                            Text('${(progress * 100).round()}%', style: theme.textTheme.labelLarge),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          color: Color(goal.color),
                          backgroundColor: Color(goal.color).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          planned == 0 && focused == 0
                              ? 'No time blocked for it this week'
                              : '${formatDuration(planned)} planned · ${formatDuration(focused)} focused this week',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
