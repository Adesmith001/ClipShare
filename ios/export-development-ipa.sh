#!/usr/bin/env bash
set -euo pipefail

: "${APPLE_TEAM_ID:?Set the APPLE_TEAM_ID environment variable}"
: "${IOS_CERTIFICATE:?Set the IOS_CERTIFICATE_BASE64 secret}"
: "${IOS_CERTIFICATE_PASSWORD?Set the IOS_CERTIFICATE_PASSWORD secret}"
: "${IOS_RUNNER_PROFILE:?Set the IOS_RUNNER_PROFILE_BASE64 secret}"
: "${IOS_EXTENSION_PROFILE:?Set the IOS_EXTENSION_PROFILE_BASE64 secret}"

work_dir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/clipshare-signing.XXXXXX")
keychain="$work_dir/clipshare.keychain-db"
trap 'security delete-keychain "$keychain" >/dev/null 2>&1 || true' EXIT
password=$(openssl rand -hex 32)
printf '%s' "$IOS_CERTIFICATE" | base64 -D > "$work_dir/certificate.p12"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$work_dir/certificate.p12" -k "$keychain" -P "$IOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain"
security list-keychains -d user -s "$keychain"

install_profile() {
  local encoded=$1
  local bundle=$2
  local profile="$work_dir/$bundle.mobileprovision"
  local plist="$work_dir/$bundle.plist"
  printf '%s' "$encoded" | base64 -D > "$profile"
  security cms -D -i "$profile" -o "$plist"
  local uuid
  uuid=$(python3 - "$plist" "$APPLE_TEAM_ID" "$bundle" <<'PY'
import plistlib
import sys

path, team, bundle = sys.argv[1:]
with open(path, 'rb') as profile_file:
    profile = plistlib.load(profile_file)
entitlements = profile['Entitlements']
if (
    team not in profile['TeamIdentifier']
    or entitlements['application-identifier'] != f'{team}.{bundle}'
    or 'group.com.adesmith001.clipshare' not in entitlements.get('com.apple.security.application-groups', [])
    or not profile.get('ProvisionedDevices')
    or not entitlements.get('get-task-allow')
):
    sys.exit(f'A development profile with the ClipShare App Group is required for {bundle}.')
print(profile['UUID'])
PY
  ) || return 1
  local profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  mkdir -p "$profiles"
  cp "$profile" "$profiles/$uuid.mobileprovision"
  printf '%s' "$uuid"
}

runner_bundle=com.adesmith001.clipshare
extension_bundle="$runner_bundle.ShareExtension"
runner_profile=$(install_profile "$IOS_RUNNER_PROFILE" "$runner_bundle")
extension_profile=$(install_profile "$IOS_EXTENSION_PROFILE" "$extension_bundle")

flutter pub get --enforce-lockfile
flutter build ios --release --config-only --no-codesign --no-pub
xcodebuild archive -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$work_dir/ClipShare.xcarchive" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Development' \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CLIPSHARE_RUNNER_PROFILE="$runner_profile" \
  CLIPSHARE_EXTENSION_PROFILE="$extension_profile"

python3 - "$work_dir/ExportOptions.plist" "$APPLE_TEAM_ID" "$runner_profile" "$extension_profile" <<'PY'
import plistlib
import sys

path, team, app, extension = sys.argv[1:]
with open(path, 'wb') as options:
    plistlib.dump({
        'method': 'debugging',
        'signingStyle': 'manual',
        'teamID': team,
        'provisioningProfiles': {
            'com.adesmith001.clipshare': app,
            'com.adesmith001.clipshare.ShareExtension': extension,
        },
    }, options)
PY

xcodebuild -exportArchive -archivePath "$work_dir/ClipShare.xcarchive" \
  -exportOptionsPlist "$work_dir/ExportOptions.plist" -exportPath build/ios/ipa

ipas=(build/ios/ipa/*.ipa)
[[ ${#ipas[@]} -eq 1 && -f "${ipas[0]}" ]]
unzip -q "${ipas[0]}" -d "$work_dir/export"
app="$work_dir/export/Payload/Runner.app"
codesign --verify --deep --strict "$app"
for bundle in "$app" "$app/PlugIns/ShareExtension.appex"; do
  codesign -d --entitlements - --xml "$bundle" > "$work_dir/entitlements.plist"
  group=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$work_dir/entitlements.plist")
  [[ "$group" = group.com.adesmith001.clipshare ]]
done
