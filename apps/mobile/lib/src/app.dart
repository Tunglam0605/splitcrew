import 'package:flutter/material.dart';
import 'package:splitcrew_update_core/splitcrew_update_core.dart';

import 'app_state.dart';
import 'home_page.dart';
import 'member_sync_workspace.dart';
import 'payment_ui.dart';
import 'receipt_ui.dart';
import 'settings_page.dart';
import 'sync_service.dart';
import 'sync_ui.dart';
import 'update_service.dart';

final class SplitCrewApp extends StatelessWidget {
  const SplitCrewApp({
    super.key,
    required this.controller,
    required this.sync,
    required this.updates,
  });

  final TripController controller;
  final MobileSyncController sync;
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
        animation: Listenable.merge([controller, sync]),
        builder: (context, _) {
          final isMember = sync.isMemberSession;
          final page = controller.hasTrip
              ? isMember
                  ? MemberSyncedWorkspace(controller: controller, sync: sync)
                  : TripWorkspace(controller: controller)
              : CreateTripPage(controller: controller, loadError: controller.loadError);

          return Stack(
            children: [
              Positioned.fill(child: page),
              if (!controller.hasTrip)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: SafeArea(
                    child: FloatingActionButton.extended(
                      heroTag: 'join-crew',
                      tooltip: 'Join a crew on the local network',
                      onPressed: sync.busy
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => JoinCrewPage(sync: sync),
                                ),
                              ),
                      icon: const Icon(Icons.group_add_rounded),
                      label: const Text('Join crew'),
                    ),
                  ),
                ),
              if (controller.hasTrip && !isMember)
                Positioned(
                  left: 16,
                  bottom: 72,
                  child: SafeArea(
                    child: FloatingActionButton.small(
                      heroTag: 'receipt-center',
                      tooltip: 'Receipt evidence',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReceiptCenterPage(controller: controller),
                        ),
                      ),
                      child: const Icon(Icons.photo_camera_back_outlined),
                    ),
                  ),
                ),
              if (controller.hasTrip && !isMember)
                Positioned(
                  left: 16,
                  bottom: 128,
                  child: SafeArea(
                    child: AnimatedBuilder(
                      animation: sync,
                      builder: (context, _) {
                        return FloatingActionButton.small(
                          heroTag: 'crew-sync',
                          tooltip: sync.isHostRunning ? 'Host Session running' : 'Crew sync',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SyncCenterPage(controller: controller, sync: sync),
                            ),
                          ),
                          child: Icon(
                            sync.isHostRunning ? Icons.wifi_tethering_rounded : Icons.sync_alt_rounded,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                bottom: controller.hasTrip
                    ? isMember
                        ? 16
                        : 184
                    : 16,
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
