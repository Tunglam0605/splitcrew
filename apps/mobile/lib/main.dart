import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_state.dart';
import 'src/update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = TripController();
  await controller.load();
  final updates = await UpdateController.bootstrap();
  runApp(SplitCrewApp(controller: controller, updates: updates));

  // Network failure must never block local/offline startup.
  unawaited(updates.checkForUpdates());
}
