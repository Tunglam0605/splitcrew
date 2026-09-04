import 'package:pub_semver/pub_semver.dart';

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  readyToInstall,
  failed,
}

final class ReleaseArtifact {
  const ReleaseArtifact({
    required this.version,
    required this.tagName,
    required this.releasePageUrl,
    required this.apkUrl,
    required this.checksumUrl,
    required this.notes,
    required this.prerelease,
  });

  final Version version;
  final String tagName;
  final Uri releasePageUrl;
  final Uri apkUrl;
  final Uri checksumUrl;
  final String notes;
  final bool prerelease;
}

final class UpdateSnapshot {
  const UpdateSnapshot({
    required this.status,
    required this.installedVersion,
    this.availableRelease,
    this.downloadedApkPath,
    this.errorMessage,
  });

  factory UpdateSnapshot.idle(Version installedVersion) => UpdateSnapshot(
        status: UpdateStatus.idle,
        installedVersion: installedVersion,
      );

  final UpdateStatus status;
  final Version installedVersion;
  final ReleaseArtifact? availableRelease;
  final String? downloadedApkPath;
  final String? errorMessage;

  UpdateSnapshot copyWith({
    UpdateStatus? status,
    ReleaseArtifact? availableRelease,
    String? downloadedApkPath,
    String? errorMessage,
    bool clearError = false,
  }) =>
      UpdateSnapshot(
        status: status ?? this.status,
        installedVersion: installedVersion,
        availableRelease: availableRelease ?? this.availableRelease,
        downloadedApkPath: downloadedApkPath ?? this.downloadedApkPath,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      );
}

Version parseAppVersion(String raw) {
  final clean = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
  return Version.parse(clean);
}

bool shouldOfferRelease({
  required Version installed,
  required ReleaseArtifact candidate,
}) {
  if (candidate.version <= installed) return false;

  // Stable installations stay on the stable channel. Alpha/beta/RC builds are
  // allowed to see prereleases so testers can move forward without reinstalling.
  if (!installed.isPreRelease && candidate.prerelease) return false;
  return true;
}

ReleaseArtifact? selectBestRelease({
  required Version installed,
  required Iterable<ReleaseArtifact> releases,
}) {
  final candidates = releases
      .where((release) => shouldOfferRelease(installed: installed, candidate: release))
      .toList()
    ..sort((a, b) => b.version.compareTo(a.version));
  return candidates.isEmpty ? null : candidates.first;
}
