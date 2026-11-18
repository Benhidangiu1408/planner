import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../util/dates.dart';

enum BlockDragKind { move, resize }

/// A block positioned on a timeline, possibly sharing its time with others.
class PlacedBlock {
  PlacedBlock(this.block, this.start, this.end);

  final TimeBlock block;
  final int start;
  final int end;
  int column = 0;
  int columns = 1;
}

/// Places overlapping blocks side by side in columns (greedy, per cluster).
List<PlacedBlock> layoutBlocks(Iterable<PlacedBlock> input) {
  final items = input.toList()
    ..sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : b.end.compareTo(a.end));
  final result = <PlacedBlock>[];
  var cluster = <PlacedBlock>[];
  var columnEnds = <int>[];
  var clusterEnd = -1;

  void flush() {
    for (final p in cluster) {
      p.columns = columnEnds.length;
    }
    result.addAll(cluster);
    cluster = [];
    columnEnds = [];
    clusterEnd = -1;
  }

  for (final p in items) {
    if (cluster.isNotEmpty && p.start >= clusterEnd) flush();
    var col = columnEnds.indexWhere((end) => end <= p.start);
    if (col == -1) {
      col = columnEnds.length;
      columnEnds.add(p.end);
    } else {
      columnEnds[col] = p.end;
    }
    p.column = col;
    cluster.add(p);
    clusterEnd = max(clusterEnd, p.end);
  }
  flush();
  return result;
}

/// Shared look and gestures for a time block on any timeline.
///
/// Mouse: drag to move, drag the bottom edge to resize.
/// Touch: long-press then drag to move, so normal swipes still scroll.
class BlockTile extends StatelessWidget {
  const BlockTile({
    super.key,
    required this.block,
    required this.start,
    required this.end,
    required this.goal,
    required this.use24h,
    required this.onTap,
    required this.onToggleDone,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    this.onFocus,
    this.dragging = false,
    this.focusing = false,
    this.focusMinutes = 0,
  });

  final TimeBlock block;
  final int start;
  final int end;
  final Goal? goal;
  final bool use24h;
  final bool dragging;

  /// Whether the focus timer is running for this block.
  final bool focusing;

  /// Minutes logged with the focus timer for this block.
  final int focusMinutes;
  final VoidCallback onTap;
  final VoidCallback onToggleDone;
  final VoidCallback? onFocus;
  final void Function(BlockDragKind kind, Offset globalPosition) onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(block.color);
    final dark = theme.brightness == Brightness.dark;
    final background = Color.alphaBlend(
      color.withValues(alpha: dark ? 0.32 : 0.16),
      scheme.surface,
    );
    final timeText = '${formatClock(start, use24h: use24h)} – ${formatClock(end, use24h: use24h)}';
    final titleStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: block.done ? scheme.onSurfaceVariant : scheme.onSurface,
      decoration: block.done ? TextDecoration.lineThrough : null,
    );
    final metaStyle = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final repeating = block.routineId != null;

    Widget metaRow(IconData icon, String text, {Color? iconColor}) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: iconColor ?? scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text, style: metaStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final w = constraints.maxWidth;
        final compact = h < 44;
        final showToggle = w >= 72;
        final showFocus = onFocus != null && w >= 200 && !compact;
        final rightPad = showToggle ? (showFocus ? 54.0 : 28.0) : 4.0;

        final Widget content = compact
            ? Row(
                children: [
                  if (repeating) ...[
                    Icon(Icons.repeat, size: 12, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                  ],
                  Flexible(
                    child: Text(
                      block.title,
                      style: titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      timeText,
                      style: metaStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.title,
                    style: titleStyle,
                    maxLines: h > 92 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      if (repeating) ...[
                        Icon(Icons.repeat, size: 12, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          w >= 130 ? '$timeText · ${formatDuration(end - start)}' : timeText,
                          style: metaStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (goal != null && h > 66)
                    metaRow(Icons.flag, goal!.title, iconColor: Color(goal!.color)),
                  if ((focusMinutes > 0 || focusing) && h > 84)
                    metaRow(
                      Icons.timer_outlined,
                      focusing
                          ? 'Focusing now · ${formatDuration(focusMinutes)} so far'
                          : '${formatDuration(focusMinutes)} focused of ${formatDuration(end - start)}',
                      iconColor: focusing ? scheme.primary : null,
                    ),
                  if (block.notes.isNotEmpty && h > 120)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        block.notes,
                        style: metaStyle,
                        maxLines: ((h - 110) / 16).floor().clamp(1, 8),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              );

        final tile = Material(
          color: background,
          elevation: dragging ? 6 : 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: focusing ? BorderSide(color: scheme.primary, width: 2) : BorderSide.none,
          ),
          child: InkWell(
            onTap: onTap,
            mouseCursor: dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: color)),
                Padding(
                  padding: EdgeInsets.fromLTRB(10, compact ? 3 : 6, rightPad, 4),
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: content,
                    ),
                  ),
                ),
                if (showToggle)
                  Positioned(
                    top: compact ? -4 : 2,
                    right: 2,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showFocus)
                          _TinyButton(
                            tooltip: focusing ? 'Focus timer running' : 'Start focus timer',
                            icon: focusing ? Icons.timer : Icons.play_circle_outline,
                            color: focusing ? scheme.primary : scheme.outline,
                            onPressed: focusing ? null : onFocus,
                          ),
                        _TinyButton(
                          tooltip: block.done ? 'Mark as not done' : 'Mark as done',
                          icon: block.done ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: block.done ? color : scheme.outline,
                          onPressed: onToggleDone,
                        ),
                      ],
                    ),
                  ),
                // Resize handle along the bottom edge.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (d) =>
                          onDragStart(BlockDragKind.resize, d.globalPosition),
                      onVerticalDragUpdate: (d) => onDragUpdate(d.globalPosition),
                      onVerticalDragEnd: (_) => onDragEnd(),
                      onVerticalDragCancel: onDragCancel,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        return GestureDetector(
          supportedDevices: const {PointerDeviceKind.mouse},
          onPanStart: (d) => onDragStart(BlockDragKind.move, d.globalPosition),
          onPanUpdate: (d) => onDragUpdate(d.globalPosition),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragCancel,
          child: GestureDetector(
            supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus},
            onLongPressStart: (d) {
              HapticFeedback.selectionClick();
              onDragStart(BlockDragKind.move, d.globalPosition);
            },
            onLongPressMoveUpdate: (d) => onDragUpdate(d.globalPosition),
            onLongPressEnd: (_) => onDragEnd(),
            onLongPressCancel: onDragCancel,
            child: tile,
          ),
        );
      },
    );
  }
}

class _TinyButton extends StatelessWidget {
  const _TinyButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    iconSize: 18,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 26, height: 26),
    onPressed: onPressed,
    icon: Icon(icon, color: color),
    disabledColor: color,
  );
}
