#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodegen generate --spec project.yml
common=(-project ReproductorPersonal.xcodeproj -scheme ReproductorPersonal -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages CODE_SIGNING_ALLOWED=NO)
case "${1:-}" in
  test|test-unit)
    simulator=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; devices=json.load(sys.stdin)["devices"]; phones=[d["udid"] for runtime,items in devices.items() if ".iOS-" in runtime for d in items if d.get("isAvailable") and d["name"].startswith("iPhone")]; sys.exit("No available iPhone simulator") if not phones else print(phones[0])')
    xcrun simctl boot "$simulator" 2>/dev/null || true
    xcrun simctl bootstatus "$simulator" -b
    selection=(test)
    if [ "$1" = test-unit ]; then selection+=(-only-testing:ReproductorPersonalTests); fi
    xcodebuild "${common[@]}" "${selection[@]}" -destination "platform=iOS Simulator,id=$simulator" -parallel-testing-enabled NO -resultBundlePath "build/Tests-$(date +%s).xcresult" 2>&1 | tee build/tests.log
    xcrun simctl launch --terminate-running-process "$simulator" personal.reproductor.ios
    sleep 2
    xcrun simctl io "$simulator" screenshot build/preview.png
    ;;
  ipa)
    xcodebuild "${common[@]}" build -configuration Release -destination 'generic/platform=iOS' 2>&1 | tee build/ipa.log
    app=build/DerivedData/Build/Products/Release-iphoneos/ReproductorPersonal.app
    test -f "$app/Info.plist"
    executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
    test -f "$app/$executable"
    mkdir -p build/Payload
    ditto "$app" build/Payload/ReproductorPersonal.app
    ditto -c -k --keepParent build/Payload build/ReproductorPersonal.ipa
    unzip -l build/ReproductorPersonal.ipa | tee build/contents.log
    unzip -Z1 build/ReproductorPersonal.ipa | grep -Fx 'Payload/ReproductorPersonal.app/Info.plist'
    unzip -Z1 build/ReproductorPersonal.ipa | grep -Fx "Payload/ReproductorPersonal.app/$executable"
    ;;
  *) printf 'Usage: bash scripts/ci.sh test|test-unit|ipa\n' >&2; exit 2 ;;
esac
