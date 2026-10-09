#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$repo_dir/build/release}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodebuild -project "$repo_dir/AssetFlow.xcodeproj" -scheme AssetFlow \
  -sdk iphoneos -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$output_dir/DerivedData" CODE_SIGNING_ALLOWED=NO build \
  > "$output_dir/build.log" 2>&1 || { tail -80 "$output_dir/build.log"; exit 1; }
app_path="$output_dir/DerivedData/Build/Products/Release-iphoneos/AssetFlow.app"
package_dir="$(mktemp -d "$output_dir/package.XXXXXX")"
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "$package_dir/Payload"
# ditto preserves the native app bundle's metadata and executable permissions.
ditto "$app_path" "$package_dir/Payload/AssetFlow.app"
ditto -c -k --norsrc --noextattr --keepParent "$package_dir/Payload" "$output_dir/AssetFlow.ipa"
python3 "$repo_dir/Scripts/release-metadata.py" "$output_dir/AssetFlow.ipa" "$output_dir/update.json"
printf 'IPA: %s\nManifest: %s\n' "$output_dir/AssetFlow.ipa" "$output_dir/update.json"
