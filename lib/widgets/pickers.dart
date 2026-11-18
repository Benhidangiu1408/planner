import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../data/planner_scope.dart';
import '../util/dates.dart';

/// Start/end time buttons plus quick duration chips.
class TimeRangePicker extends StatelessWidget {
  const TimeRangePicker({
    super.key,
    required this.start,
    required this.end,
    required this.onChanged,
    this.error,
  });

  final int start;
  final int end;
  final void Function(int start, int end) onChanged;
  final String? error;

  Future<void> _pick(BuildContext context, {required bool isStart}) async {
    final use24h = PlannerScope.read(context).settings.use24h;
    final current = isStart ? start : end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (current ~/ 60) % 24, minute: current % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24h),
        child: child!,
      ),
    );
    if (picked == null) return;
    var minutes = picked.hour * 60 + picked.minute;
    if (isStart) {
      // Moving the start keeps the duration.
      final duration = end > start ? end - start : 60;
      final s = min(minutes, 1440 - 5);
      onChanged(s, min(s + duration, 1440));
    } else {
      if (minutes == 0) minutes = 1440; // midnight means end of day
      onChanged(start, minutes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final use24h = PlannerScope.of(context).settings.use24h;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _TimeField(
                label: 'Start',
                text: formatClock(start, use24h: use24h),
                onTap: () => _pick(context, isStart: true),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, size: 18),
            ),
            Expanded(
              child: _TimeField(
                label: 'End',
                text: formatClock(end, use24h: use24h),
                onTap: () => _pick(context, isStart: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final d in const [15, 30, 45, 60, 90, 120, 180])
              ChoiceChip(
                label: Text(formatDuration(d)),
                selected: end - start == d,
                onSelected: (_) => onChanged(start, min(start + d, 1440)),
              ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.label, required this.text, required this.onTap});

  final String label;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule, size: 18),
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}

/// Monday–Sunday toggles. An empty list means "every day".
class WeekdayPicker extends StatelessWidget {
  const WeekdayPicker({super.key, required this.weekdays, required this.onChanged});

  final List<int> weekdays;
  final ValueChanged<List<int>> onChanged;

  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  void _toggle(int day, bool on) {
    final set = weekdays.isEmpty ? {1, 2, 3, 4, 5, 6, 7} : weekdays.toSet();
    on ? set.add(day) : set.remove(day);
    if (set.isEmpty) set.add(day); // keep at least one day
    onChanged(set.length == 7 ? const [] : (set.toList()..sort()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(_names[d - 1]),
                selected: weekdays.isEmpty || weekdays.contains(d),
                onSelected: (on) => _toggle(d, on),
              ),
          ],
        ),
        Wrap(
          children: [
            TextButton(onPressed: () => onChanged(const []), child: const Text('Every day')),
            TextButton(
              onPressed: () => onChanged(const [1, 2, 3, 4, 5]),
              child: const Text('Weekdays'),
            ),
            TextButton(onPressed: () => onChanged(const [6, 7]), child: const Text('Weekends')),
          ],
        ),
      ],
    );
  }
}
