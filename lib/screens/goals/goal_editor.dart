import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/planner_scope.dart';
import '../../util/dates.dart';
import '../../util/palette.dart';
import '../../widgets/common.dart';

Future<void> showGoalEditor(
  BuildContext context, {
  Goal? goal,
  Horizon? horizon,
  String? parentId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _GoalEditor(goal: goal, horizon: horizon, parentId: parentId),
  );
}

class _GoalEditor extends StatefulWidget {
  const _GoalEditor({this.goal, this.horizon, this.parentId});

  final Goal? goal;
  final Horizon? horizon;
  final String? parentId;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  late final _title = TextEditingController(text: widget.goal?.title ?? '');
  late final _description = TextEditingController(text: widget.goal?.description ?? '');
  final _newMilestone = TextEditingController();

  late Horizon _horizon = widget.goal?.horizon ?? widget.horizon ?? Horizon.month;
  late DateTime? _due = widget.goal?.dueDate != null
      ? parseDateKey(widget.goal!.dueDate!)
      : (widget.goal == null ? _horizon.defaultDue(today()) : null);
  late bool _dueTouched = widget.goal != null;
  late String? _parentId = widget.goal?.parentId ?? widget.parentId;
  late int _color =
      widget.goal?.color ??
      PlannerScope.read(context).goalById(_parentId)?.color ??
      plannerColors[(PlannerScope.read(context).goals.length + 1) % plannerColors.length];
  late final List<Milestone> _milestones = [...?widget.goal?.milestones];
  late bool _completed = widget.goal?.completed ?? false;
  String? _titleError;

  bool get _isNew => widget.goal == null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _newMilestone.dispose();
    super.dispose();
  }

  void _addMilestone() {
    final text = _newMilestone.text.trim();
    if (text.isEmpty) return;
    setState(() => _milestones.add(Milestone(id: newId(), title: text)));
    _newMilestone.clear();
  }

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? today(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _due = picked;
        _dueTouched = true;
      });
    }
  }

  void _setHorizon(Horizon h) {
    final store = PlannerScope.read(context);
    setState(() {
      _horizon = h;
      if (!_dueTouched) _due = h.defaultDue(today());
      // A parent must look further ahead than its sub-goal.
      if (!store.parentCandidates(widget.goal, h).any((g) => g.id == _parentId)) {
        _parentId = null;
      }
    });
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Give your goal a name.');
      return;
    }
    _addMilestone(); // don't lose a milestone that was typed but not added
    final store = PlannerScope.read(context);
    final dueKey = _due == null ? null : dateKey(_due!);
    final parentId = _parentId;
    final goal =
        (widget.goal ??
                Goal(
                  id: newId(),
                  title: title,
                  horizon: _horizon,
                  color: _color,
                  createdAt: DateTime.now().millisecondsSinceEpoch,
                ))
            .copyWith(
              title: title,
              description: _description.text.trim(),
              horizon: _horizon,
              dueDate: () => dueKey,
              color: _color,
              milestones: List.of(_milestones),
              completed: _completed,
              parentId: () => parentId,
            );
    store.saveGoal(goal);
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final store = PlannerScope.read(context);
    final navigator = Navigator.of(context);
    final ok = await confirmAction(
      context,
      title: 'Delete goal?',
      message:
          'Linked tasks, time blocks and sub-goals are kept but will no longer point to this goal.',
    );
    if (!ok) return;
    store.deleteGoal(widget.goal!.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = PlannerScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _milestones.where((m) => m.done).length;
    final parents = store.parentCandidates(widget.goal, _horizon);
    final children = widget.goal == null ? const <Goal>[] : store.childrenOf(widget.goal!.id);

    return AlertDialog(
      title: Text(_isNew ? (_parentId != null ? 'New sub-goal' : 'New goal') : 'Edit goal'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Goal',
                  hintText: 'e.g. Run a 10K, ship the portfolio site',
                  errorText: _titleError,
                ),
              ),
              const SizedBox(height: 16),
              Text('Horizon', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final h in Horizon.values)
                    ChoiceChip(
                      label: Text(h.label),
                      selected: _horizon == h,
                      onSelected: (_) => _setHorizon(h),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Part of',
                  helperText: 'Link it to a bigger, longer-term goal',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: parents.any((g) => g.id == _parentId) ? _parentId : null,
                    onChanged: parents.isEmpty ? null : (id) => setState(() => _parentId = id),
                    disabledHint: Text(
                      _horizon == Horizon.longTerm
                          ? 'Long-term goals are the top level'
                          : 'No goal with a longer horizon yet',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Nothing (top level)'),
                      ),
                      for (final g in parents)
                        DropdownMenuItem<String?>(
                          value: g.id,
                          child: Row(
                            children: [
                              ColorDot(g.color),
                              const SizedBox(width: 10),
                              Expanded(child: Text(g.title, overflow: TextOverflow.ellipsis)),
                              Text(
                                g.horizon.label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDue,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(
                      _due == null ? 'Set a deadline' : 'Due ${DateFormat.yMMMd().format(_due!)}',
                    ),
                  ),
                  if (_due != null)
                    IconButton(
                      tooltip: 'Remove deadline',
                      onPressed: () => setState(() {
                        _due = null;
                        _dueTouched = true;
                      }),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Color', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              ColorPickerRow(selected: _color, onChanged: (c) => setState(() => _color = c)),
              const SizedBox(height: 16),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Why it matters / details (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('Milestones', style: theme.textTheme.labelLarge),
                  const SizedBox(width: 8),
                  if (_milestones.isNotEmpty)
                    Text(
                      '$done/${_milestones.length}',
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < _milestones.length; i++)
                Row(
                  children: [
                    Checkbox(
                      value: _milestones[i].done,
                      onChanged: (v) => setState(
                        () => _milestones[i] = _milestones[i].copyWith(done: v ?? false),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _milestones[i].title,
                        style: TextStyle(
                          decoration: _milestones[i].done ? TextDecoration.lineThrough : null,
                          color: _milestones[i].done ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Move up',
                      visualDensity: VisualDensity.compact,
                      onPressed: i == 0
                          ? null
                          : () =>
                                setState(() => _milestones.insert(i - 1, _milestones.removeAt(i))),
                      icon: const Icon(Icons.arrow_upward, size: 16),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _milestones.removeAt(i)),
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              TextField(
                controller: _newMilestone,
                decoration: InputDecoration(
                  hintText: 'Add a milestone, press Enter',
                  prefixIcon: const Icon(Icons.add),
                  suffixIcon: IconButton(
                    tooltip: 'Add milestone',
                    onPressed: _addMilestone,
                    icon: const Icon(Icons.keyboard_return, size: 18),
                  ),
                ),
                onSubmitted: (_) => _addMilestone(),
                onEditingComplete: () {},
              ),
              if (children.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Sub-goals', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  'Each sub-goal counts like a milestone towards this goal\'s progress.',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                for (final c in children)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        ColorDot(c.color),
                        const SizedBox(width: 10),
                        Expanded(child: Text(c.title)),
                        Text(
                          '${c.horizon.label} · ${(store.progressOf(c) * 100).round()}%',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (!_isNew) ...[
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _completed,
                  onChanged: (v) => setState(() => _completed = v),
                  title: const Text('Achieved'),
                  subtitle: const Text('Moves the goal to the Achieved list'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!_isNew)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
