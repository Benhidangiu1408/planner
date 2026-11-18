import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/planner_scope.dart';
import '../util/dates.dart';
import 'common.dart';

const maxFocusGoals = 3;

/// Lets the user pick up to three focus goals and an intention for a week.
Future<void> showWeekFocusEditor(BuildContext context, DateTime weekStart) {
  return showDialog<void>(
    context: context,
    builder: (_) => _WeekFocusEditor(weekStart: dateKey(startOfWeek(weekStart))),
  );
}

String weekRangeLabel(DateTime anyDay) {
  final start = startOfWeek(anyDay);
  final end = addDays(start, 6);
  final sameMonth = start.month == end.month;
  return sameMonth
      ? '${DateFormat.MMMd().format(start)} – ${end.day}, ${end.year}'
      : '${DateFormat.MMMd().format(start)} – ${DateFormat.MMMd().format(end)}, ${end.year}';
}

class _WeekFocusEditor extends StatefulWidget {
  const _WeekFocusEditor({required this.weekStart});

  final String weekStart;

  @override
  State<_WeekFocusEditor> createState() => _WeekFocusEditorState();
}

class _WeekFocusEditorState extends State<_WeekFocusEditor> {
  late final WeekPlan _plan = PlannerScope.read(context).weekPlan(widget.weekStart);
  late final Set<String> _focus = {..._plan.focusGoalIds};
  late final _intention = TextEditingController(text: _plan.intention);

  @override
  void dispose() {
    _intention.dispose();
    super.dispose();
  }

  void _save() {
    final store = PlannerScope.read(context);
    // Re-read so reflection text edited elsewhere isn't overwritten.
    store.saveWeekPlan(
      store
          .weekPlan(widget.weekStart)
          .copyWith(focusGoalIds: _focus.toList(), intention: _intention.text.trim()),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final goals = store.goals.where((g) => !g.completed).toList()
      ..sort((a, b) => a.horizon.index.compareTo(b.horizon.index));

    return AlertDialog(
      title: Text('Focus for ${weekRangeLabel(parseDateKey(widget.weekStart))}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pick up to $maxFocusGoals goals to concentrate on. They show up on the Day and Week views.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (goals.isEmpty)
                const Text('Create a goal first, then come back to pick your focus.')
              else
                FocusGoalChips(
                  goals: goals,
                  selected: _focus,
                  onToggle: (id) =>
                      setState(() => _focus.contains(id) ? _focus.remove(id) : _focus.add(id)),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _intention,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Intention for the week (optional)',
                  hintText: 'e.g. Protect mornings for deep work',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Selectable goal chips, limited to [maxFocusGoals].
class FocusGoalChips extends StatelessWidget {
  const FocusGoalChips({
    super.key,
    required this.goals,
    required this.selected,
    required this.onToggle,
  });

  final List<Goal> goals;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final full = selected.length >= maxFocusGoals;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final g in goals)
          FilterChip(
            avatar: ColorDot(g.color),
            label: Text(g.title),
            tooltip: g.horizon.label,
            selected: selected.contains(g.id),
            onSelected: full && !selected.contains(g.id) ? null : (_) => onToggle(g.id),
          ),
      ],
    );
  }
}

/// One-line summary of the week's focus with an edit shortcut.
class WeekFocusStrip extends StatelessWidget {
  const WeekFocusStrip({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final plan = store.weekPlan(dateKey(startOfWeek(day)));
    final goals = store.focusGoalsFor(day);

    if (goals.isEmpty && plan.intention.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => showWeekFocusEditor(context, day),
          icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
          label: const Text("Set this week's focus"),
        ),
      );
    }
    final strip = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showWeekFocusEditor(context, day),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.center_focus_strong, size: 18, color: scheme.primary),
            Text('Week focus', style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
            for (final g in goals)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Color(g.color).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ColorDot(g.color, size: 8),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${g.title} · ${(store.progressOf(g) * 100).round()}%',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            if (plan.intention.isNotEmpty)
              Text(
                '"${plan.intention}"',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
    return Align(alignment: Alignment.centerLeft, child: strip);
  }
}
