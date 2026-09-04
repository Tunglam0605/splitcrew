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
if ! grep -q 'android.permission.REQUEST_INSTALL_PACKAGES' "$manifest"; then
  python3 - "$manifest" <<'PY'
from pathlib import Path
import sys
manifest = Path(sys.argv[1])
text = manifest.read_text()
permission = '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n'
text = text.replace('<application', permission + '    <application', 1)
manifest.write_text(text)
PY
fi

cd "$mobile_dir"
flutter pub get

echo 'Android platform generated with updater permission. Run: cd apps/mobile && flutter run'
