import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_update_core/splitcrew_update_core.dart';

abstract interface class UpdateProvider {
  Future<List<ReleaseArtifact>> fetchReleases();
  Future<String> downloadVerifiedApk(ReleaseArtifact release);
  Future<void> installApk(String path);
}

final class GithubReleaseUpdateProvider implements UpdateProvider {
  GithubReleaseUpdateProvider({http.Client? client}) : _client = client ?? http.Client();

  static final Uri _releasesUri = Uri.parse(
    'https://api.github.com/repos/Tunglam0605/splitcrew/releases?per_page=20',
  );

  final http.Client _client;

  @override
  Future<List<ReleaseArtifact>> fetchReleases() async {
    final response = await _client.get(
      _releasesUri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (response.statusCode != 200) {
      throw HttpException('GitHub Releases returned HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw const FormatException('Unexpected GitHub Releases response.');
    final releases = <ReleaseArtifact>[];
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final json = Map<String, dynamic>.from(raw);
      final parsed = _parseRelease(json);
      if (parsed != null) releases.add(parsed);
    }
    return releases;
  }

  ReleaseArtifact? _parseRelease(Map<String, dynamic> json) {
    if (json['draft'] == true) return null;
    final tagName = json['tag_name'] as String?;
    final pageUrl = json['html_url'] as String?;
    if (tagName == null || pageUrl == null) return null;

    Version version;
    try {
      version = parseAppVersion(tagName);
    } on FormatException {
      return null;
    }

    final assets = (json['assets'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((asset) => Map<String, dynamic>.from(asset))
        .toList();
    final apk = assets.where((asset) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      return name.endsWith('.apk') && name.contains('splitcrew');
    }).firstOrNull;
    if (apk == null) return null;
    final apkName = apk['name'] as String;
    final checksum = assets.where((asset) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      return name == '${apkName.toLowerCase()}.sha256' ||
          (name.endsWith('.sha256') && name.contains('splitcrew'));
    }).firstOrNull;
    if (checksum == null) return null;

    final apkUrl = apk['browser_download_url'] as String?;
    final checksumUrl = checksum['browser_download_url'] as String?;
    if (apkUrl == null || checksumUrl == null) return null;

    return ReleaseArtifact(
      version: version,
      tagName: tagName,
      releasePageUrl: Uri.parse(pageUrl),
      apkUrl: Uri.parse(apkUrl),
      checksumUrl: Uri.parse(checksumUrl),
      notes: json['body'] as String? ?? '',
      prerelease: json['prerelease'] == true,
    );
  }

  @override
  Future<String> downloadVerifiedApk(ReleaseArtifact release) async {
    final checksumResponse = await _client.get(release.checksumUrl);
    if (checksumResponse.statusCode != 200) {
      throw HttpException('Checksum download returned HTTP ${checksumResponse.statusCode}.');
    }
    final checksumMatch = RegExp(r'\b[a-fA-F0-9]{64}\b').firstMatch(checksumResponse.body);
    if (checksumMatch == null) throw const FormatException('Release checksum is invalid.');
    final expectedChecksum = checksumMatch.group(0)!.toLowerCase();

    final request = http.Request('GET', release.apkUrl);
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('APK download returned HTTP ${response.statusCode}.');
    }

    final root = await getApplicationSupportDirectory();
    final updatesDir = Directory('${root.path}${Platform.pathSeparator}updates');
    await updatesDir.create(recursive: true);
    final safeVersion = release.version.toString().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${updatesDir.path}${Platform.pathSeparator}splitcrew-$safeVersion.apk');
    final fileSink = file.openWrite();
    final digestOutput = AccumulatorSink<Digest>();
    final digestInput = sha256.startChunkedConversion(digestOutput);
    try {
      await for (final chunk in response.stream) {
        fileSink.add(chunk);
        digestInput.add(chunk);
      }
      digestInput.close();
      await fileSink.close();
    } catch (_) {
      digestInput.close();
      await fileSink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }

    final actualChecksum = digestOutput.events.single.toString().toLowerCase();
    if (actualChecksum != expectedChecksum) {
      if (await file.exists()) await file.delete();
      throw StateError('Downloaded APK checksum verification failed.');
    }
    return file.path;
  }

  @override
  Future<void> installApk(String path) async {
    final file = File(path);
    if (!await file.exists()) throw StateError('Prepared APK no longer exists.');
    await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
  }
}

final class UpdateController extends ChangeNotifier {
  UpdateController({
    required Version installedVersion,
    required UpdateProvider provider,
    SharedPreferences? preferences,
  })  : _provider = provider,
        _preferences = preferences,
        _snapshot = UpdateSnapshot.idle(installedVersion);

  static const _lastCheckKey = 'splitcrew.update.last_check_ms';
  static const _automaticCheckInterval = Duration(hours: 6);

  final UpdateProvider _provider;
  SharedPreferences? _preferences;
  UpdateSnapshot _snapshot;

  UpdateSnapshot get snapshot => _snapshot;
  String get installedVersionLabel => _snapshot.installedVersion.toString();

  static Future<UpdateController> bootstrap() async {
    final info = await PackageInfo.fromPlatform();
    final preferences = await SharedPreferences.getInstance();
    return UpdateController(
      installedVersion: parseAppVersion(info.version),
      provider: GithubReleaseUpdateProvider(),
      preferences: preferences,
    );
  }

  Future<void> checkForUpdates({bool manual = false}) async {
    if (_snapshot.status == UpdateStatus.checking || _snapshot.status == UpdateStatus.downloading) return;
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    if (!manual) {
      final last = preferences.getInt(_lastCheckKey);
      if (last != null) {
        final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last));
        if (elapsed < _automaticCheckInterval) return;
      }
    }

    _set(_snapshot.copyWith(status: UpdateStatus.checking, clearError: true));
    try {
      final releases = await _provider.fetchReleases();
      final best = selectBestRelease(
        installed: _snapshot.installedVersion,
        releases: releases,
      );
      await preferences.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      if (best == null) {
        _snapshot = UpdateSnapshot(
          status: UpdateStatus.upToDate,
          installedVersion: _snapshot.installedVersion,
        );
      } else {
        _snapshot = UpdateSnapshot(
          status: UpdateStatus.updateAvailable,
          installedVersion: _snapshot.installedVersion,
          availableRelease: best,
        );
      }
      notifyListeners();
    } catch (error) {
      _set(UpdateSnapshot(
        status: UpdateStatus.failed,
        installedVersion: _snapshot.installedVersion,
        availableRelease: _snapshot.availableRelease,
        errorMessage: 'Update check failed: $error',
      ));
    }
  }

  Future<void> downloadUpdate() async {
    final release = _snapshot.availableRelease;
    if (release == null) return;
    _set(_snapshot.copyWith(status: UpdateStatus.downloading, clearError: true));
    try {
      final path = await _provider.downloadVerifiedApk(release);
      _set(UpdateSnapshot(
        status: UpdateStatus.readyToInstall,
        installedVersion: _snapshot.installedVersion,
        availableRelease: release,
        downloadedApkPath: path,
      ));
    } catch (error) {
      _set(UpdateSnapshot(
        status: UpdateStatus.failed,
        installedVersion: _snapshot.installedVersion,
        availableRelease: release,
        errorMessage: 'Update download failed: $error',
      ));
    }
  }

  Future<void> installPreparedUpdate() async {
    final path = _snapshot.downloadedApkPath;
    if (path == null) return;
    try {
      await _provider.installApk(path);
    } catch (error) {
      _set(_snapshot.copyWith(status: UpdateStatus.failed, errorMessage: 'Installer launch failed: $error'));
    }
  }

  void dismissError() {
    _snapshot = UpdateSnapshot.idle(_snapshot.installedVersion);
    notifyListeners();
  }

  void _set(UpdateSnapshot next) {
    _snapshot = next;
    notifyListeners();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
