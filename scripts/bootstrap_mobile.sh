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

cd "$mobile_dir"
flutter pub get

echo 'Android platform generated. Run: cd apps/mobile && flutter run'
