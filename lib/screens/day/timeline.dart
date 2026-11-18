import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/planner_scope.dart';
import '../../data/planner_store.dart';
import '../../util/dates.dart';
import '../../widgets/block_tile.dart';
import '../../widgets/common.dart';
import '../../widgets/editors.dart';
import '../../widgets/routines.dart';
import '../../widgets/task_drag.dart';

/// Vertical, time-blocked schedule for one day.
///
/// * Click/tap an empty slot to add a block, or drop a task on it.
/// * Drag a block (mouse) or long-press then drag (touch) to move it.
/// * Drag its bottom edge to resize. Everything snaps to 15 minutes.
class DayTimeline extends StatefulWidget {
  const DayTimeline({super.key, required this.date});

  final DateTime date;

  @override
  State<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<DayTimeline> {
  static const double hourHeight = 64;
  static const double gutter = 58;
  static const int snapMinutes = 15;

  final _scroll = ScrollController();
  final _canvasKey = GlobalKey();
  Timer? _ticker;
  int? _hoverMinute;
  int? _dropMinute;

  String? _dragId;
  BlockDragKind _dragKind = BlockDragKind.move;
  Offset _dragOrigin = Offset.zero;
  Offset _dragDelta = Offset.zero;

  // Visible range in minutes; recomputed every build.
  int _rangeStart = 0;
  int _rangeEnd = 1440;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus(animate: false));
  }

  @override
  void didUpdateWidget(DayTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isSameDay(oldWidget.date, widget.date)) {
      _dragId = null;
      _hoverMinute = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  double _y(int minute) => (minute - _rangeStart) / 60 * hourHeight;

  int _snap(double minutes) => (minutes / snapMinutes).round() * snapMinutes;

  /// Half-hour slot under a vertical position in the canvas.
  int _slotAt(double dy) {
    final minute = _rangeStart + (dy / hourHeight * 60).floor();
    return ((minute ~/ 30) * 30).clamp(_rangeStart, max(_rangeStart, _rangeEnd - 30));
  }

  /// 15-minute slot under a global position (for drops).
  int? _minuteAtGlobal(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(global);
    final minute = _rangeStart + (local.dy / hourHeight * 60);
    return ((minute / snapMinutes).floor() * snapMinutes)
        .clamp(_rangeStart, max(_rangeStart, _rangeEnd - 15))
        .toInt();
  }

  /// Scrolls to "now" on today, otherwise to the first block (or 8:00).
  void _scrollToFocus({bool animate = true}) {
    if (!mounted || !_scroll.hasClients) return;
    final blocks = PlannerScope.read(context).blocksOn(dateKey(widget.date));
    final now = DateTime.now();
    final int target;
    if (isSameDay(widget.date, now)) {
      target = now.hour * 60 + now.minute - 90;
    } else if (blocks.isNotEmpty) {
      target = blocks.first.start - 30;
    } else {
      target = 8 * 60;
    }
    final offset = _y(target).clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(offset);
    }
  }

  /// Start/end of a block, taking an in-progress drag into account.
  (int, int) _effective(TimeBlock b) {
    if (b.id != _dragId) return (b.start, b.end);
    final deltaMinutes = _dragDelta.dy / hourHeight * 60;
    if (_dragKind == BlockDragKind.move) {
      final duration = b.duration;
      final start = _snap(b.start + deltaMinutes).clamp(_rangeStart, _rangeEnd - duration);
      return (start, start + duration);
    }
    final end = _snap(b.end + deltaMinutes).clamp(b.start + snapMinutes, _rangeEnd);
    return (b.start, end);
  }

  void _startDrag(TimeBlock b, BlockDragKind kind, Offset global) {
    setState(() {
      _dragId = b.id;
      _dragKind = kind;
      _dragOrigin = global;
      _dragDelta = Offset.zero;
      _hoverMinute = null;
    });
  }

  void _updateDrag(Offset global) {
    if (_dragId == null) return;
    setState(() => _dragDelta = global - _dragOrigin);
  }

  void _endDrag(PlannerStore store, TimeBlock b) {
    if (_dragId != b.id) return;
    final (start, end) = _effective(b);
    final distance = _dragDelta.distance;
    setState(() => _dragId = null);
    if (start != b.start || end != b.end) {
      store.saveBlock(b.copyWith(start: start, end: end));
    } else if (distance < 4) {
      // A click with a tiny wobble: treat it as a tap.
      showBlockEditor(context, date: b.date, block: b);
    }
  }

  void _cancelDrag() {
    if (_dragId != null) setState(() => _dragId = null);
  }

  Future<void> _addAt(int start) async {
    setState(() => _hoverMinute = null);
    await showBlockEditor(
      context,
      date: dateKey(widget.date),
      start: start,
      end: min(start + 60, 1440),
    );
  }

  void _addNext(PlannerStore store) {
    final now = DateTime.now();
    final from = isSameDay(widget.date, now)
        ? min(((now.hour * 60 + now.minute) ~/ 30 + 1) * 30, 1380)
        : max(9 * 60, store.settings.dayStartHour * 60);
    _addAt(store.suggestStart(dateKey(widget.date), from: from));
  }

  Future<void> _onMenu(String action, PlannerStore store) async {
    final key = dateKey(widget.date);
    switch (action) {
      case 'copy_prev':
        final n = store.copyBlocks(from: dateKey(addDays(widget.date, -1)), to: key);
        if (mounted) {
          showMessage(
            context,
            n == 0
                ? 'The previous day has no one-off blocks.'
                : 'Copied $n block${n == 1 ? '' : 's'}.',
          );
        }
      case 'copy_next':
        final n = store.copyBlocks(from: key, to: dateKey(addDays(widget.date, 1)));
        if (mounted) {
          showMessage(
            context,
            n == 0 ? 'Nothing to copy.' : 'Copied $n block${n == 1 ? '' : 's'} to the next day.',
          );
        }
      case 'routines':
        await showRoutineManager(context);
      case 'focus':
        store.startFocus();
      case 'clear':
        final ok = await confirmAction(
          context,
          title: 'Clear this day?',
          message:
              'All time blocks on this day will be removed (routines skip this day). '
              'Tasks and notes stay.',
          confirmLabel: 'Clear',
        );
        if (ok) store.clearBlocks(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final settings = store.settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final blocks = store.blocksOn(dateKey(widget.date));

    // Stretch the visible range so no block is ever hidden.
    var startHour = settings.dayStartHour;
    var endHour = settings.dayEndHour;
    for (final b in blocks) {
      startHour = min(startHour, b.start ~/ 60);
      endHour = max(endHour, (b.end + 59) ~/ 60);
    }
    _rangeStart = startHour * 60;
    _rangeEnd = endHour * 60;

    final total = blocks.fold(0, (sum, b) => sum + b.duration);
    final doneCount = blocks.where((b) => b.done).length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 420;
                return Row(
                  children: [
                    if (!narrow) ...[
                      Icon(Icons.view_timeline_outlined, size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      'Schedule',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        blocks.isEmpty
                            ? (narrow
                                  ? 'Tap a slot to plan it'
                                  : 'Click a slot or drop a task here')
                            : '${formatDuration(total)} · $doneCount/${blocks.length} done',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    if (narrow)
                      IconButton.filledTonal(
                        tooltip: 'Add block',
                        onPressed: () => _addNext(store),
                        icon: const Icon(Icons.add),
                      )
                    else
                      FilledButton.tonalIcon(
                        onPressed: () => _addNext(store),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Block'),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: (a) => _onMenu(a, store),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'focus',
                          child: ListTile(
                            leading: Icon(Icons.timer_outlined),
                            title: Text('Start a focus session'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'routines',
                          child: ListTile(leading: Icon(Icons.repeat), title: Text('Routines…')),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'copy_prev',
                          child: ListTile(
                            leading: Icon(Icons.content_copy),
                            title: Text('Copy schedule from previous day'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'copy_next',
                          child: ListTile(
                            leading: Icon(Icons.redo),
                            title: Text('Copy schedule to next day'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'clear',
                          child: ListTile(
                            leading: Icon(Icons.delete_sweep_outlined),
                            title: Text('Clear this day'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(0, 14, 10, 14),
                child: DragTarget<Task>(
                  onMove: (d) {
                    final m = _minuteAtGlobal(d.offset);
                    if (m != _dropMinute) setState(() => _dropMinute = m);
                  },
                  onLeave: (_) => setState(() => _dropMinute = null),
                  onAcceptWithDetails: (d) {
                    final m = _minuteAtGlobal(d.offset);
                    setState(() => _dropMinute = null);
                    if (m != null) scheduleTask(context, d.data, dateKey(widget.date), m);
                  },
                  builder: (context, candidates, _) => SizedBox(
                    key: _canvasKey,
                    height: (endHour - startHour) * hourHeight,
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          _canvas(context, store, blocks, startHour, endHour, constraints.maxWidth),
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

  Widget _ghost(BuildContext context, int minute, int minutes, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: _y(minute) + 1,
      left: gutter + 4,
      right: 4,
      height: minutes / 60 * hourHeight - 2,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.06),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.primary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _canvas(
    BuildContext context,
    PlannerStore store,
    List<TimeBlock> blocks,
    int startHour,
    int endHour,
    double width,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final use24h = store.settings.use24h;
    final areaWidth = width - gutter;
    final focus = store.activeFocus;
    final children = <Widget>[];

    // Hour lines and labels.
    for (var h = startHour; h <= endHour; h++) {
      final y = _y(h * 60);
      children
        ..add(
          Positioned(
            top: y - 8,
            left: 0,
            width: gutter - 10,
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
            child: ColoredBox(color: scheme.outlineVariant),
          ),
        );
      if (h < endHour) {
        children.add(
          Positioned(
            top: y + hourHeight / 2,
            left: gutter,
            right: 0,
            height: 1,
            child: ColoredBox(color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
        );
      }
    }

    // Empty-slot hit area (beneath the blocks).
    children.add(
      Positioned(
        left: gutter,
        right: 0,
        top: 0,
        bottom: 0,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (e) {
            final slot = _slotAt(e.localPosition.dy);
            if (slot != _hoverMinute && _dragId == null) setState(() => _hoverMinute = slot);
          },
          onExit: (_) {
            if (_hoverMinute != null) setState(() => _hoverMinute = null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _addAt(_slotAt(d.localPosition.dy)),
          ),
        ),
      ),
    );

    if (_dropMinute != null) {
      children.add(
        _ghost(
          context,
          _dropMinute!,
          60,
          'Drop to schedule at ${formatClock(_dropMinute!, use24h: use24h)}',
        ),
      );
    } else if (_hoverMinute != null && _dragId == null) {
      children.add(
        _ghost(
          context,
          _hoverMinute!,
          30,
          '+ New block at ${formatClock(_hoverMinute!, use24h: use24h)}',
        ),
      );
    }

    // Blocks; the one being dragged is painted last so it stays on top.
    final placed = layoutBlocks([
      for (final b in blocks)
        () {
          final (s, e) = _effective(b);
          return PlacedBlock(b, s, e);
        }(),
    ])..sort((a, b) => (a.block.id == _dragId ? 1 : 0) - (b.block.id == _dragId ? 1 : 0));

    for (final p in placed) {
      final colWidth = (areaWidth - 4) / p.columns;
      final top = _y(p.start);
      final height = _y(p.end) - top;
      final b = p.block;
      final focusing = focus != null && focus.blockId == b.id;
      final focusMinutes =
          store.focusMinutesForBlock(b.id) +
          (focusing ? focus.elapsedMs(DateTime.now().millisecondsSinceEpoch) ~/ 60000 : 0);
      children.add(
        Positioned(
          key: ValueKey(b.id),
          top: top + 1,
          height: max(height - 2, 18),
          left: gutter + 4 + p.column * colWidth,
          width: max(colWidth - 4, 24),
          child: BlockTile(
            block: b,
            start: p.start,
            end: p.end,
            goal: store.goalById(b.goalId),
            use24h: use24h,
            dragging: b.id == _dragId,
            focusing: focusing,
            focusMinutes: focusMinutes,
            onTap: () => showBlockEditor(context, date: b.date, block: b),
            onToggleDone: () => store.toggleBlock(b.id),
            onFocus: () => store.startFocus(block: b),
            onDragStart: (kind, pos) => _startDrag(b, kind, pos),
            onDragUpdate: _updateDrag,
            onDragEnd: () => _endDrag(store, b),
            onDragCancel: _cancelDrag,
          ),
        ),
      );
    }

    // Current-time indicator.
    final now = DateTime.now();
    final nowMinute = now.hour * 60 + now.minute;
    if (isSameDay(widget.date, now) && nowMinute >= _rangeStart && nowMinute <= _rangeEnd) {
      children.add(
        Positioned(
          top: _y(nowMinute) - 4,
          left: gutter - 4,
          right: 0,
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
