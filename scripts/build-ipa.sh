#!/usr/bin/env bash
# Builds an unsigned SiteCounter.ipa into ./build (needs Xcode and XcodeGen).
# Sideload it with AltStore or Sideloadly, which sign it with your Apple ID.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild \
  -project SiteCounter.xcodeproj \
  -target SiteCounteriOS \
  -configuration Release \
  -sdk iphoneos \
  SYMROOT="$PWD/build/ios" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

rm -rf build/Payload build/SiteCounter.ipa
mkdir -p build/Payload
cp -R build/ios/Release-iphoneos/SiteCounter.app build/Payload/
(cd build && zip -qry SiteCounter.ipa Payload)
echo "Built: build/SiteCounter.ipa"
