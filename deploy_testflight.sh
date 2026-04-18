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

# ── 1. Increment version by 0.1 ────────────────────────
CURRENT_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= //;s/;//')
MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
NEW_MINOR=$((MINOR + 1))
NEW_VERSION="$MAJOR.$NEW_MINOR"

echo "📦 Bumping version: $CURRENT_VERSION → $NEW_VERSION"
sed -i '' "s/MARKETING_VERSION = $CURRENT_VERSION;/MARKETING_VERSION = $NEW_VERSION;/g" "$PBXPROJ"

# ── 2. Clean & Archive ─────────────────────────────────
echo "🔨 Archiving..."
mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR"
ARCHIVE_PATH="$ARCHIVE_DIR/ShypQuick-$NEW_VERSION.xcarchive"

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

# ── 3. Export IPA ──────────────────────────────────────
echo "📤 Exporting IPA..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID" \
  -quiet

echo "✅ IPA exported to $EXPORT_DIR"

# ── 4. Upload to TestFlight ────────────────────────────
echo "🚀 Uploading to TestFlight..."
xcrun altool --upload-app \
  -f "$EXPORT_DIR/ShypQuick.ipa" \
  -t ios \
  --apiKey "$API_KEY_ID" \
  --apiIssuer "$API_ISSUER_ID"

echo "🎉 Version $NEW_VERSION uploaded to TestFlight!"

# ── 5. Commit version bump ─────────────────────────────
cd "$PROJECT_DIR"
git add "$PBXPROJ"
git commit -m "Bump version to $NEW_VERSION for TestFlight"
git push origin main

echo "✅ Version bump committed and pushed."
