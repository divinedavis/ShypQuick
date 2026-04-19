#!/bin/bash
set -euo pipefail

# ── Config ──────────────────────────────────────────────
PROJECT_DIR="$HOME/Desktop/ShypQuick"
PROJECT="ShypQuick.xcodeproj"
SCHEME="ShypQuick"
PBXPROJ="$PROJECT_DIR/$PROJECT/project.pbxproj"

API_KEY_ID="DCW4DGNGQ4"
API_ISSUER_ID="69a6de85-d1b5-47e3-e053-5b8c7c11a4d1"
API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_DCW4DGNGQ4.p8"

ARCHIVE_DIR="$PROJECT_DIR/build/archives"
EXPORT_DIR="$PROJECT_DIR/build/export"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"

# ── 1. Increment build number ─────────────────────────
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= //;s/;//')
NEW_BUILD=$((CURRENT_BUILD + 1))
MARKETING_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= //;s/;//')

echo "📦 Bumping build: $MARKETING_VERSION ($CURRENT_BUILD) → $MARKETING_VERSION ($NEW_BUILD)"
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"

# ── 2. Archive ────────────────────────────────────────
echo "🔨 Archiving..."
mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR"
ARCHIVE_PATH="$ARCHIVE_DIR/ShypQuick-$MARKETING_VERSION-$NEW_BUILD.xcarchive"

cd "$PROJECT_DIR"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID" \
  -quiet

echo "✅ Archive created: $ARCHIVE_PATH"

# ── 3. Export & Upload ────────────────────────────────
echo "📤 Exporting & uploading..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID" \
  -quiet

echo "🎉 $MARKETING_VERSION ($NEW_BUILD) uploaded to TestFlight!"

# ── 4. Commit build bump ─────────────────────────────
cd "$PROJECT_DIR"
git add "$PBXPROJ"
git commit -m "Build $NEW_BUILD for TestFlight [$MARKETING_VERSION]"
git push origin main

echo "✅ Build bump committed and pushed."
