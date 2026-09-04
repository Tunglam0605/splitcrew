import 'package:flutter/material.dart';
import 'package:splitcrew_update_core/splitcrew_update_core.dart';

import 'app_state.dart';
import 'home_page.dart';
import 'payment_ui.dart';
import 'settings_page.dart';
import 'update_service.dart';

final class SplitCrewApp extends StatelessWidget {
  const SplitCrewApp({
    super.key,
    required this.controller,
    required this.updates,
  });

  final TripController controller;
  final UpdateController updates;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SplitCrew',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3157D5)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final page = controller.hasTrip
              ? TripWorkspace(controller: controller)
              : CreateTripPage(controller: controller, loadError: controller.loadError);
          return Stack(
            children: [
              Positioned.fill(child: page),
              Positioned(
                left: 16,
                bottom: controller.hasTrip ? 72 : 16,
                child: SafeArea(
                  child: AnimatedBuilder(
                    animation: updates,
                    builder: (context, _) {
                      final hasUpdate = updates.snapshot.status == UpdateStatus.updateAvailable ||
                          updates.snapshot.status == UpdateStatus.readyToInstall;
                      return FloatingActionButton.small(
                        heroTag: 'settings-update',
                        tooltip: hasUpdate ? 'Update available' : 'Settings & updates',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SettingsPage(updates: updates),
                          ),
                        ),
                        child: Icon(hasUpdate ? Icons.system_update_alt_rounded : Icons.settings_rounded),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
