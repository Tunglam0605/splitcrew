import 'package:flutter/material.dart';
import 'package:splitcrew_update_core/splitcrew_update_core.dart';

import 'update_service.dart';

final class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.updates});

  final UpdateController updates;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: updates,
      builder: (context, _) {
        final snapshot = updates.snapshot;
        final release = snapshot.availableRelease;
        return Scaffold(
          appBar: AppBar(title: const Text('Settings & About')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SplitCrew', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text('Installed version: ${updates.installedVersionLabel}'),
                      const SizedBox(height: 4),
                      const Text('Distribution channel: GitHub Releases'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('App updates', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text(
                'SplitCrew checks for updates without blocking offline use. APK updates are downloaded only from the official repository and verified by SHA-256 before Android is asked to install them.',
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _UpdateStatusText(snapshot: snapshot),
                      if (release != null) ...[
                        const SizedBox(height: 10),
                        Text('Available: ${release.tagName}', style: Theme.of(context).textTheme.titleMedium),
                        if (release.notes.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            release.notes.trim(),
                            maxLines: 8,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: snapshot.status == UpdateStatus.checking ||
                                    snapshot.status == UpdateStatus.downloading
                                ? null
                                : () => updates.checkForUpdates(manual: true),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Check for updates'),
                          ),
                          if (snapshot.status == UpdateStatus.updateAvailable)
                            FilledButton.icon(
                              onPressed: updates.downloadUpdate,
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('Download update'),
                            ),
                          if (snapshot.status == UpdateStatus.readyToInstall)
                            FilledButton.icon(
                              onPressed: updates.installPreparedUpdate,
                              icon: const Icon(Icons.system_update_rounded),
                              label: const Text('Install update'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Android security remains in control of installation. SplitCrew never silently installs an APK and never deletes local trip or payment data during an app update.',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

final class _UpdateStatusText extends StatelessWidget {
  const _UpdateStatusText({required this.snapshot});

  final UpdateSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (snapshot.status) {
      UpdateStatus.idle => (Icons.info_outline_rounded, 'Update status has not been checked yet.'),
      UpdateStatus.checking => (Icons.sync_rounded, 'Checking GitHub Releases…'),
      UpdateStatus.upToDate => (Icons.check_circle_outline_rounded, 'You are up to date.'),
      UpdateStatus.updateAvailable => (Icons.new_releases_outlined, 'A newer compatible version is available.'),
      UpdateStatus.downloading => (Icons.downloading_rounded, 'Downloading and verifying the APK…'),
      UpdateStatus.readyToInstall => (Icons.verified_rounded, 'APK checksum verified. Ready for Android installation.'),
      UpdateStatus.failed => (Icons.error_outline_rounded, snapshot.errorMessage ?? 'Update operation failed.'),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}
