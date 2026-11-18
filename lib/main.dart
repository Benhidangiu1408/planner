import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'data/planner_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await PlannerStore.load();
  runApp(PlannerApp(store: store));
}
