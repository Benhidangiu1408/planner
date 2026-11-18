import 'dart:async';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/planner_scope.dart';
import '../data/planner_store.dart';
import '../util/dates.dart';
import '../widgets/block_tile.dart';
import '../widgets/common.dart';
import '../widgets/editors.dart';
import '../widgets/task_drag.dart';
import '../widgets/week_focus.dart';

/// Medium-range planning: seven timelines side by side. Blocks can be dragged
/// between days, tasks between days or onto a timeline to schedule them.
class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key, required this.onOpenDay});

  final ValueChanged<DateTime> onOpenDay;

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  DateTime _weekStart = startOfWeek(today());

  void _shift(int weeks) => setState(() => _weekStart = addDays(_weekStart, 7 * weeks));

  @override
  Widget build(BuildContext context) {
    final isThisWeek = isSameDay(_weekStart, startOfWeek(today()));
    return Column(
      children: [
        PageHeader(
          title: 'Week',
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
                  : () => setState(() => _weekStart = startOfWeek(today())),
              child: const Text('This week'),
            ),
            IconButton(
              tooltip: 'Next week',
              onPressed: () => _shift(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: WeekFocusStrip(day: _weekStart),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 900
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: _WeekGrid(weekStart: _weekStart, onOpenDay: widget.onOpenDay),
                  )
                : _WeekAgenda(weekStart: _weekStart, onOpenDay: widget.onOpenDay),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- wide: grid

class _WeekGrid extends StatefulWidget {
  const _WeekGrid({required this.weekStart, required this.onOpenDay});

  final DateTime weekStart;
  final ValueChanged<DateTime> onOpenDay;

  @override
  State<_WeekGrid> createState() => _WeekGridState();
}

class _WeekGridState extends State<_WeekGrid> {
  static const double hourHeight = 52;
  static const double gutter = 52;
  static const double trayHeight = 112;
  static const int snapMinutes = 15;

  final _scroll = ScrollController();
  final _canvasKey = GlobalKey();
  Timer? _ticker;

  String? _dragId;
  BlockDragKind _dragKind = BlockDragKind.move;
  Offset _dragOrigin = Offset.zero;
  Offset _dragDelta = Offset.zero;
  (int, int)? _drop; // (day index, minute) while a task hovers the grid

  int _rangeStart = 0;
  int _rangeEnd = 1440;
  double _colWidth = 100;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final now = DateTime.now();
      final target = (now.hour * 60 + now.minute - 120).clamp(8 * 60 - 30, 1440);
      _scroll.jumpTo(_y(target).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  List<DateTime> get _days => [for (var i = 0; i < 7; i++) addDays(widget.weekStart, i)];

  double _y(int minute) => (minute - _rangeStart) / 60 * hourHeight;

  int _snap(double minutes) => (minutes / snapMinutes).round() * snapMinutes;

  (int, int)? _slotAtGlobal(Offset global, {int step = 15}) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(global);
    if (local.dx < gutter) return null;
    final day = ((local.dx - gutter) / _colWidth).floor().clamp(0, 6);
    final minute = _rangeStart + local.dy / hourHeight * 60;
    final snapped = ((minute / step).floor() * step)
        .clamp(_rangeStart, max(_rangeStart, _rangeEnd - step))
        .toInt();
    return (day, snapped);
  }

  /// Day index and times of a block, including an in-progress drag.
  (int, int, int) _effective(TimeBlock b, int dayIndex) {
    if (b.id != _dragId) return (dayIndex, b.start, b.end);
    final deltaMinutes = _dragDelta.dy / hourHeight * 60;
    if (_dragKind == BlockDragKind.resize) {
      return (
        dayIndex,
        b.start,
        _snap(b.end + deltaMinutes).clamp(b.start + snapMinutes, _rangeEnd),
      );
    }
    final day = (dayIndex + (_dragDelta.dx / _colWidth).round()).clamp(0, 6);
    final start = _snap(b.start + deltaMinutes).clamp(_rangeStart, _rangeEnd - b.duration);
    return (day, start, start + b.duration);
  }

  void _endDrag(PlannerStore store, TimeBlock b, int dayIndex) {
    if (_dragId != b.id) return;
    final (day, start, end) = _effective(b, dayIndex);
    final distance = _dragDelta.distance;
    setState(() => _dragId = null);
    final date = dateKey(_days[day]);
    if (date != b.date || start != b.start || end != b.end) {
      store.saveBlock(b.copyWith(date: date, start: start, end: end));
    } else if (distance < 4) {
      showBlockEditor(context, date: b.date, block: b);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = _days;
    final blocksByDay = store.blocksBetween(days.first, days.last);
    final settings = store.settings;

    var startHour = settings.dayStartHour;
    var endHour = settings.dayEndHour;
    for (final list in blocksByDay.values) {
      for (final b in list) {
        startHour = min(startHour, b.start ~/ 60);
        endHour = max(endHour, (b.end + 59) ~/ 60);
      }
    }
    _rangeStart = startHour * 60;
    _rangeEnd = endHour * 60;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Day headers.
          Row(
            children: [
              const SizedBox(width: gutter),
              for (final d in days)
                Expanded(
                  child: _DayHeader(
                    date: d,
                    plannedMinutes: (blocksByDay[dateKey(d)] ?? const []).fold(
                      0,
                      (sum, b) => sum + b.duration,
                    ),
                    onOpen: () => widget.onOpenDay(d),
                  ),
                ),
            ],
          ),
          const Divider(height: 1),
          // Task trays.
          SizedBox(
            height: trayHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: gutter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Text(
                      'Tasks',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                for (final d in days) Expanded(child: _TaskTray(date: d)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: DragTarget<Task>(
                  onMove: (d) {
                    final slot = _slotAtGlobal(d.offset);
                    if (slot != _drop) setState(() => _drop = slot);
                  },
                  onLeave: (_) => setState(() => _drop = null),
                  onAcceptWithDetails: (d) {
                    final slot = _slotAtGlobal(d.offset);
                    setState(() => _drop = null);
                    if (slot != null) {
                      scheduleTask(context, d.data, dateKey(days[slot.$1]), slot.$2);
                    }
                  },
                  builder: (context, _, _) => SizedBox(
                    key: _canvasKey,
                    height: (endHour - startHour) * hourHeight,
                    child: LayoutBuilder(
                      builder: (context, c) {
                        _colWidth = (c.maxWidth - gutter) / 7;
                        return _canvas(context, store, days, blocksByDay, startHour, endHour);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _canvas(
    BuildContext context,
    PlannerStore store,
    List<DateTime> days,
    Map<String, List<TimeBlock>> blocksByDay,
    int startHour,
    int endHour,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final use24h = store.settings.use24h;
    final focus = store.activeFocus;
    final children = <Widget>[];
    final now = DateTime.now();

    for (var h = startHour; h <= endHour; h++) {
      final y = _y(h * 60);
      children
        ..add(
          Positioned(
            top: y - 8,
            left: 0,
            width: gutter - 8,
            child: Text(
              formatClock(h * 60, use24h: use24h),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        )
        ..add(
          Positioned(
            top: y,
            left: gutter,
            right: 0,
            height: 1,
            child: ColoredBox(color: scheme.outlineVariant.withValues(alpha: 0.7)),
          ),
        );
    }

    for (var i = 0; i < 7; i++) {
      final isToday = isSameDay(days[i], now);
      children.add(
        Positioned(
          top: 0,
          bottom: 0,
          left: gutter + i * _colWidth,
          width: _colWidth,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isToday ? scheme.primary.withValues(alpha: 0.04) : null,
                border: Border(
                  left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Click an empty slot to add a block on that day.
    children.add(
      Positioned(
        left: gutter,
        right: 0,
        top: 0,
        bottom: 0,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final slot = _slotAtGlobal(d.globalPosition, step: 30);
              if (slot == null) return;
              showBlockEditor(
                context,
                date: dateKey(days[slot.$1]),
                start: slot.$2,
                end: min(slot.$2 + 60, 1440),
              );
            },
          ),
        ),
      ),
    );

    if (_drop != null) {
      final (day, minute) = _drop!;
      children.add(
        Positioned(
          top: _y(minute),
          left: gutter + day * _colWidth + 3,
          width: _colWidth - 6,
          height: hourHeight - 2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                border: Border.all(color: scheme.primary),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  formatClock(minute, use24h: use24h),
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Blocks, grouped by the day they are (or are being dragged) on.
    final perDay = List.generate(7, (_) => <PlacedBlock>[]);
    final dayOfBlock = <String, int>{};
    for (var i = 0; i < 7; i++) {
      for (final b in blocksByDay[dateKey(days[i])] ?? const <TimeBlock>[]) {
        final (day, s, e) = _effective(b, i);
        dayOfBlock[b.id] = i;
        perDay[day].add(PlacedBlock(b, s, e));
      }
    }
    final placedBlocks = <(int, PlacedBlock)>[
      for (var day = 0; day < 7; day++)
        for (final p in layoutBlocks(perDay[day])) (day, p),
    ]..sort((a, b) => (a.$2.block.id == _dragId ? 1 : 0) - (b.$2.block.id == _dragId ? 1 : 0));

    for (final (day, p) in placedBlocks) {
      final b = p.block;
      final colWidth = (_colWidth - 6) / p.columns;
      final top = _y(p.start);
      final focusing = focus != null && focus.blockId == b.id;
      children.add(
        Positioned(
          key: ValueKey(b.id),
          top: top + 1,
          height: max(_y(p.end) - top - 2, 16),
          left: gutter + day * _colWidth + 3 + p.column * colWidth,
          width: max(colWidth - 2, 20),
          child: BlockTile(
            block: b,
            start: p.start,
            end: p.end,
            goal: store.goalById(b.goalId),
            use24h: use24h,
            dragging: b.id == _dragId,
            focusing: focusing,
            focusMinutes: store.focusMinutesForBlock(b.id),
            onTap: () => showBlockEditor(context, date: b.date, block: b),
            onToggleDone: () => store.toggleBlock(b.id),
            onFocus: () => store.startFocus(block: b),
            onDragStart: (kind, pos) => setState(() {
              _dragId = b.id;
              _dragKind = kind;
              _dragOrigin = pos;
              _dragDelta = Offset.zero;
            }),
            onDragUpdate: (pos) {
              if (_dragId == b.id) setState(() => _dragDelta = pos - _dragOrigin);
            },
            onDragEnd: () => _endDrag(store, b, dayOfBlock[b.id]!),
            onDragCancel: () {
              if (_dragId != null) setState(() => _dragId = null);
            },
          ),
        ),
      );
    }

    // Now line on today's column.
    final todayIndex = days.indexWhere((d) => isSameDay(d, now));
    final nowMinute = now.hour * 60 + now.minute;
    if (todayIndex >= 0 && nowMinute >= _rangeStart && nowMinute <= _rangeEnd) {
      children.add(
        Positioned(
          top: _y(nowMinute) - 4,
          left: gutter + todayIndex * _colWidth - 4,
          width: _colWidth + 4,
          height: 8,
          child: IgnorePointer(
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                ),
                Expanded(child: Container(height: 2, color: scheme.error)),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.plannedMinutes, required this.onOpen});

  final DateTime date;
  final int plannedMinutes;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isToday = isSameDay(date, today());
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? scheme.primary : null,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${date.day}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isToday ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat.E().format(date),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isToday ? scheme.primary : null,
                    ),
                  ),
                  Text(
                    plannedMinutes == 0 ? '—' : formatDuration(plannedMinutes),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Add a task',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: () => showQuickAddTask(context, dateKey(date)),
              icon: const Icon(Icons.add_task),
            ),
          ],
        ),
      ),
    );
  }
}

/// A day's tasks; drop a task here to move it to this day.
class _TaskTray extends StatelessWidget {
  const _TaskTray({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final key = dateKey(date);
    final tasks = store.tasksOn(key);

    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => d.data.date != key,
      onAcceptWithDetails: (d) => store.moveTasks([d.data.id], key),
      builder: (context, candidates, _) => Container(
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? scheme.primary.withValues(alpha: 0.08) : null,
          border: Border(left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7))),
        ),
        child: tasks.isEmpty
            ? Center(
                child: Text(
                  candidates.isNotEmpty ? 'Move here' : '',
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(4),
                children: [
                  for (final t in tasks)
                    TaskDraggable(
                      task: t,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => showTaskEditor(context, t),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                          child: Row(
                            children: [
                              InkResponse(
                                radius: 14,
                                onTap: () => store.toggleTask(t.id),
                                child: Icon(
                                  t.done ? Icons.check_box : Icons.check_box_outline_blank,
                                  size: 16,
                                  color: t.done ? scheme.primary : scheme.outline,
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (t.important)
                                Icon(Icons.star_rounded, size: 13, color: Colors.amber.shade600),
                              Expanded(
                                child: Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    decoration: t.done ? TextDecoration.lineThrough : null,
                                    color: t.done ? scheme.onSurfaceVariant : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------- narrow: agenda

class _WeekAgenda extends StatelessWidget {
  const _WeekAgenda({required this.weekStart, required this.onOpenDay});

  final DateTime weekStart;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'Long-press a task to drag it to another day.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        for (var i = 0; i < 7; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AgendaDay(date: addDays(weekStart, i), onOpenDay: onOpenDay),
          ),
      ],
    );
  }
}

class _AgendaDay extends StatelessWidget {
  const _AgendaDay({required this.date, required this.onOpenDay});

  final DateTime date;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final key = dateKey(date);
    final blocks = store.blocksOn(key);
    final tasks = store.tasksOn(key);
    final use24h = store.settings.use24h;
    final isToday = isSameDay(date, today());
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => d.data.date != key,
      onAcceptWithDetails: (d) => store.moveTasks([d.data.id], key),
      builder: (context, candidates, _) => Card(
        shape: candidates.isNotEmpty || isToday
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.primary, width: candidates.isNotEmpty ? 2 : 1),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    DateFormat.MMMEd().format(date),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isToday ? scheme.primary : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      blocks.isEmpty
                          ? ''
                          : formatDuration(blocks.fold(0, (s, b) => s + b.duration)),
                      style: muted,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add a task',
                    onPressed: () => showQuickAddTask(context, key),
                    icon: const Icon(Icons.add_task, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Open day',
                    onPressed: () => onOpenDay(date),
                    icon: const Icon(Icons.open_in_new, size: 20),
                  ),
                ],
              ),
              if (blocks.isEmpty && tasks.isEmpty)
                Text(candidates.isNotEmpty ? 'Drop to move here' : 'Nothing planned', style: muted),
              for (final b in blocks)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => showBlockEditor(context, date: b.date, block: b),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Color(b.color),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: use24h ? 92 : 128,
                          child: Text(
                            '${formatClock(b.start, use24h: use24h)}–${formatClock(b.end, use24h: use24h)}',
                            style: muted,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            b.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              decoration: b.done ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        if (b.routineId != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(Icons.repeat, size: 14, color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ),
              for (final t in tasks)
                TaskDraggable(
                  task: t,
                  longPress: true,
                  child: Row(
                    children: [
                      Checkbox(
                        visualDensity: VisualDensity.compact,
                        value: t.done,
                        onChanged: (_) => store.toggleTask(t.id),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => showTaskEditor(context, t),
                          child: Text(
                            t.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              decoration: t.done ? TextDecoration.lineThrough : null,
                              color: t.done ? scheme.onSurfaceVariant : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
