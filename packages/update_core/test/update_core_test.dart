import 'package:pub_semver/pub_semver.dart';
import 'package:splitcrew_update_core/splitcrew_update_core.dart';
import 'package:test/test.dart';

ReleaseArtifact release(String version, {bool prerelease = false}) => ReleaseArtifact(
      version: Version.parse(version),
      tagName: 'v$version',
      releasePageUrl: Uri.parse('https://example.com/$version'),
      apkUrl: Uri.parse('https://example.com/$version.apk'),
      checksumUrl: Uri.parse('https://example.com/$version.sha256'),
      notes: '',
      prerelease: prerelease,
    );

void main() {
  test('parses versions with a v prefix', () {
    expect(parseAppVersion('v1.2.3-beta.1'), Version.parse('1.2.3-beta.1'));
  });

  test('stable install ignores prerelease-only update', () {
    final result = selectBestRelease(
      installed: Version.parse('1.0.0'),
      releases: [release('1.1.0-beta.1', prerelease: true)],
    );
    expect(result, isNull);
  });

  test('prerelease install can advance to a newer prerelease', () {
    final result = selectBestRelease(
      installed: Version.parse('0.4.0-alpha.1'),
      releases: [
        release('0.4.0-alpha.2', prerelease: true),
        release('0.3.0'),
      ],
    );
    expect(result?.version, Version.parse('0.4.0-alpha.2'));
  });

  test('selects the highest compatible newer version', () {
    final result = selectBestRelease(
      installed: Version.parse('1.0.0'),
      releases: [release('1.0.1'), release('1.2.0'), release('1.1.0')],
    );
    expect(result?.version, Version.parse('1.2.0'));
  });

  test('does not offer equal or older versions', () {
    final result = selectBestRelease(
      installed: Version.parse('1.2.0'),
      releases: [release('1.2.0'), release('1.1.9')],
    );
    expect(result, isNull);
  });
}
