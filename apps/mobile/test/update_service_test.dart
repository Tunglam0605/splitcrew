import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_mobile/src/update_service.dart';
import 'package:splitcrew_update_core/splitcrew_update_core.dart';

final class FakeUpdateProvider implements UpdateProvider {
  FakeUpdateProvider({this.releases = const [], this.fetchError});

  final List<ReleaseArtifact> releases;
  final Object? fetchError;
  bool installed = false;

  @override
  Future<List<ReleaseArtifact>> fetchReleases() async {
    if (fetchError != null) throw fetchError!;
    return releases;
  }

  @override
  Future<String> downloadVerifiedApk(ReleaseArtifact release) async => '/tmp/splitcrew.apk';

  @override
  Future<void> installApk(String path) async {
    installed = true;
  }
}

ReleaseArtifact release(String version) => ReleaseArtifact(
      version: Version.parse(version),
      tagName: 'v$version',
      releasePageUrl: Uri.parse('https://example.com/release'),
      apkUrl: Uri.parse('https://example.com/app.apk'),
      checksumUrl: Uri.parse('https://example.com/app.apk.sha256'),
      notes: 'Test release',
      prerelease: version.contains('-'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('moves to updateAvailable when a newer release exists', () async {
    final preferences = await SharedPreferences.getInstance();
    final controller = UpdateController(
      installedVersion: Version.parse('0.4.0-alpha.1'),
      provider: FakeUpdateProvider(releases: [release('0.4.0-alpha.2')]),
      preferences: preferences,
    );

    await controller.checkForUpdates(manual: true);

    expect(controller.snapshot.status, UpdateStatus.updateAvailable);
    expect(controller.snapshot.availableRelease?.version, Version.parse('0.4.0-alpha.2'));
  });

  test('network failure becomes failed state without throwing', () async {
    final preferences = await SharedPreferences.getInstance();
    final controller = UpdateController(
      installedVersion: Version.parse('0.4.0-alpha.1'),
      provider: FakeUpdateProvider(fetchError: StateError('offline')),
      preferences: preferences,
    );

    await controller.checkForUpdates(manual: true);

    expect(controller.snapshot.status, UpdateStatus.failed);
    expect(controller.snapshot.errorMessage, contains('offline'));
  });

  test('download transitions to checksum-verified readyToInstall state', () async {
    final preferences = await SharedPreferences.getInstance();
    final provider = FakeUpdateProvider(releases: [release('0.4.0-alpha.2')]);
    final controller = UpdateController(
      installedVersion: Version.parse('0.4.0-alpha.1'),
      provider: provider,
      preferences: preferences,
    );

    await controller.checkForUpdates(manual: true);
    await controller.downloadUpdate();

    expect(controller.snapshot.status, UpdateStatus.readyToInstall);
    expect(controller.snapshot.downloadedApkPath, '/tmp/splitcrew.apk');
  });
}
