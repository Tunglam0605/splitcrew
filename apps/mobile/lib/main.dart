import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_state.dart';
import 'src/sync_service.dart';
import 'src/update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = TripController();
  await controller.load();
  final sync = await MobileSyncController.bootstrap(controller);
  final updates = await UpdateController.bootstrap();
  runApp(SplitCrewApp(controller: controller, sync: sync, updates: updates));

  // Network failure must never block local/offline startup.
  unawaited(updates.checkForUpdates());
}
