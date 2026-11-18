import 'package:flutter/widgets.dart';

import 'planner_store.dart';

/// Makes the [PlannerStore] available to the widget tree and rebuilds
/// dependents when it changes.
class PlannerScope extends InheritedNotifier<PlannerStore> {
  const PlannerScope({super.key, required PlannerStore store, required super.child})
    : super(notifier: store);

  /// Returns the store and subscribes [context] to changes.
  static PlannerStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlannerScope>()!.notifier!;

  /// Returns the store without subscribing (for callbacks).
  static PlannerStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlannerScope>()!.notifier!;
}
