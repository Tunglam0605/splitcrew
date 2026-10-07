#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mobile_dir="$repo_root/apps/mobile"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

command -v flutter >/dev/null 2>&1 || {
  echo 'Flutter is required but was not found in PATH.' >&2
  exit 1
}

flutter create \
  --platforms=android \
  --org io.github.tunglam0605 \
  --project-name splitcrew_mobile \
  "$tmp/mobile"

rm -rf "$mobile_dir/android"
cp -R "$tmp/mobile/android" "$mobile_dir/android"
cp "$tmp/mobile/.metadata" "$mobile_dir/.metadata"

manifest="$mobile_dir/android/app/src/main/AndroidManifest.xml"
python3 - "$manifest" <<'PY'
from pathlib import Path
import sys
manifest = Path(sys.argv[1])
text = manifest.read_text()
permissions = [
    'android.permission.INTERNET',
    'android.permission.CAMERA',
    'android.permission.REQUEST_INSTALL_PACKAGES',
]
for name in permissions:
    if name not in text:
        permission = f'    <uses-permission android:name="{name}" />\n'
        text = text.replace('<application', permission + '    <application', 1)
if 'android:usesCleartextTraffic=' not in text:
    text = text.replace('<application', '<application\n        android:usesCleartextTraffic="true"', 1)
manifest.write_text(text)
PY

cd "$mobile_dir"
flutter pub get

echo 'Android platform generated with camera, LAN sync, and updater permissions. Run: cd apps/mobile && flutter run'
