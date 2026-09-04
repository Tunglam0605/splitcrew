# Android Release and In-App Update Channel

SplitCrew's direct-distribution update channel is GitHub Releases. The app remains fully usable offline; update checks are best-effort and never block startup.

## Release contract

A public Android release must contain two assets with matching names:

- `SplitCrew-vX.Y.Z[-prerelease]-android.apk`
- `SplitCrew-vX.Y.Z[-prerelease]-android.apk.sha256`

The in-app updater only offers a release when both assets exist. It downloads the checksum first, downloads the APK from the official `Tunglam0605/splitcrew` release, computes SHA-256 locally, and only enables installation after the digests match.

## Versioning

`apps/mobile/pubspec.yaml` is the source app version. A release tag must equal `v<version-without-build-number>`.

Example:

```text
pubspec: 0.4.0-beta.1+7
tag:     v0.4.0-beta.1
```

Stable installs stay on stable releases. Alpha/beta/RC installs may receive newer prereleases.

## Required GitHub Actions secrets

Never commit the Android signing key or its passwords. Configure these repository secrets before the first public release:

- `SPLITCREW_ANDROID_KEYSTORE_B64` — base64-encoded release keystore
- `SPLITCREW_ANDROID_KEYSTORE_PASSWORD`
- `SPLITCREW_ANDROID_KEY_ALIAS`
- `SPLITCREW_ANDROID_KEY_PASSWORD`

The same signing identity must be preserved for every direct APK update. Losing or changing the key prevents Android from installing a new APK over an existing installation.

## Release workflow

`.github/workflows/release-android.yml` runs when a `v*` tag is pushed. It:

1. verifies the tag matches the Flutter app version;
2. requires the signing secrets;
3. generates the Android platform scaffold;
4. enables the user-authorized package installer permission;
5. configures the stable signing identity;
6. analyzes and tests the app;
7. builds the signed release APK;
8. generates SHA-256 metadata;
9. publishes both assets to GitHub Releases.

## In-app update behavior

The app checks automatically at startup at most once every six hours and also provides a manual **Check for updates** action.

State flow:

```text
idle
  -> checking
      -> upToDate
      -> updateAvailable
          -> downloading
              -> readyToInstall
      -> failed
```

Installation is never silent. After checksum verification, SplitCrew opens Android's package installer and the user decides whether to continue.

## Data safety

Updating the APK must not delete app data. SQLite schema changes must use forward migrations and remain compatible with previously released versions.

## Google Play

When a Play Store distribution channel is introduced, it should use a Play-supported in-app update adapter behind the same application-level update boundary. Direct APK installation permission should not be required for that Play build.
