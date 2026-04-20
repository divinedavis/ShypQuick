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

APP_ID="1513074382"
BETA_GROUP_ID="fb27a205-8fd8-4e99-a95e-f612e990bed8"  # ShypQuick Testers (external)

ARCHIVE_DIR="$PROJECT_DIR/build/archives"
EXPORT_DIR="$PROJECT_DIR/build/export"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"

generate_jwt() {
  python3 -c "
import jwt, os
from time import time
from datetime import datetime, timedelta
dt = datetime.now() + timedelta(minutes=19)
headers = {'alg': 'ES256', 'kid': '$API_KEY_ID', 'typ': 'JWT'}
payload = {'iss': '$API_ISSUER_ID', 'iat': int(time()), 'exp': int(dt.timestamp()), 'aud': 'appstoreconnect-v1'}
with open(os.path.expanduser('$API_KEY_PATH'), 'rb') as f:
    key = f.read()
print(jwt.encode(payload, key, algorithm='ES256', headers=headers))
"
}

# ── 0. Pre-flight: require clean working tree ─────────
# Otherwise the build-bump commit would drag in whatever random edits the
# user had in flight, potentially leaking secrets or half-finished code.
cd "$PROJECT_DIR"
DIRTY=$(git status --porcelain)
if [ -n "$DIRTY" ]; then
  echo "❌ Working tree is dirty. Commit or stash first:"
  echo "$DIRTY"
  exit 1
fi

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

# ── 5. Wait for processing, then distribute ──────────
echo "⏳ Waiting for Apple to process build..."
sleep 30  # Initial wait for build to appear

JWT=$(generate_jwt)

# Find the new build by version number
for attempt in $(seq 1 20); do
  BUILD_ID=$(curl -s "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=$APP_ID&filter%5Bversion%5D=$NEW_BUILD&fields%5Bbuilds%5D=version,processingState" \
    -H "Authorization: Bearer $JWT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
builds=d.get('data',[])
if builds and builds[0]['attributes']['processingState']=='VALID':
    print(builds[0]['id'])
" 2>/dev/null)

  if [ -n "$BUILD_ID" ]; then
    echo "✅ Build processed: $BUILD_ID"
    break
  fi
  echo "   Still processing... (attempt $attempt/20)"
  sleep 15
done

if [ -z "$BUILD_ID" ]; then
  echo "⚠️  Build not ready after 5 minutes. Add to group manually."
  exit 0
fi

# Set export compliance
curl -s -X PATCH "https://api.appstoreconnect.apple.com/v1/builds/$BUILD_ID" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d "{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\",\"attributes\":{\"usesNonExemptEncryption\":false}}}" > /dev/null

echo "✅ Export compliance set"

# Submit for beta review
curl -s -X POST "https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d "{\"data\":{\"type\":\"betaAppReviewSubmissions\",\"relationships\":{\"build\":{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}}}}}" > /dev/null

echo "📋 Submitted for Beta App Review"

# Wait for approval then add to group
for attempt in $(seq 1 40); do
  sleep 20
  # Refresh JWT if needed (every ~15 min)
  if [ $attempt -eq 15 ]; then JWT=$(generate_jwt); fi

  REVIEW_STATE=$(curl -s "https://api.appstoreconnect.apple.com/v1/builds/$BUILD_ID/betaAppReviewSubmission" \
    -H "Authorization: Bearer $JWT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('data',{}).get('attributes',{}).get('betaReviewState','UNKNOWN'))
" 2>/dev/null)

  echo "   Review state: $REVIEW_STATE (attempt $attempt/20)"

  if [ "$REVIEW_STATE" = "APPROVED" ]; then
    # Add build to external group
    curl -s -X POST "https://api.appstoreconnect.apple.com/v1/betaGroups/$BETA_GROUP_ID/relationships/builds" \
      -H "Authorization: Bearer $JWT" \
      -H "Content-Type: application/json" \
      -d "{\"data\":[{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}]}" > /dev/null

    echo "🚀 Build $NEW_BUILD added to ShypQuick Testers group!"
    exit 0
  fi
done

echo "⚠️  Beta review not approved after 13 minutes. Will auto-distribute when approved."
