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

# ── 0. Pre-flight: no uncommitted *tracked* changes ───
# The build-bump commit uses explicit `git add $PBXPROJ` so untracked
# files (stale dirs, Supabase CLI temps) can't sneak in. But staged or
# modified tracked files could, so block on those.
cd "$PROJECT_DIR"
DIRTY=$(git status --porcelain | grep -v '^??' || true)
if [ -n "$DIRTY" ]; then
  echo "❌ Tracked files have uncommitted changes. Commit or stash first:"
  echo "$DIRTY"
  exit 1
fi

# ── 0. Run the full test sweep ────────────────────────
# Unit tests (XCTest) + Swift Testing + performance + XCUITest must all
# pass before we ship. Failed tests = no TestFlight upload.
echo "🧪 Running full test sweep..."
"$PROJECT_DIR/scripts/run_tests.sh" all
echo "✅ All tests passed"

# ── 1. Increment build number ─────────────────────────
# Scoped to the app target (and its LiveActivity extension, which Apple
# requires to share a build number) via Ruby xcodeproj. The previous
# `grep -m1` approach broke once test targets were added — they have
# their own CURRENT_PROJECT_VERSION at 1 that grep happily picked up.
read NEW_BUILD MARKETING_VERSION <<< "$(ruby -r xcodeproj -e "
proj = Xcodeproj::Project.open('$PROJECT_DIR/$PROJECT')
app  = proj.targets.find { |t| t.product_type == 'com.apple.product-type.application' }
ext  = proj.targets.find { |t| t.product_type == 'com.apple.product-type.app-extension' }
cur  = app.build_configurations.first.build_settings['CURRENT_PROJECT_VERSION'].to_i
mkt  = app.build_configurations.first.build_settings['MARKETING_VERSION']
nxt  = cur + 1
[app, ext].compact.each do |t|
  t.build_configurations.each { |c| c.build_settings['CURRENT_PROJECT_VERSION'] = nxt.to_s }
end
proj.save
puts \"#{nxt} #{mkt}\"
")"
echo "📦 Bumping build to $MARKETING_VERSION ($NEW_BUILD)"

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
# Snapshot the set of existing build IDs BEFORE we upload so the
# polling step in §5 can pick the build that didn't exist yet — a
# version-number filter alone is unreliable because ASC silently bumps
# on conflict, and a "newest in last 30 min" filter can grab a build
# that was already finished while ours is still PROCESSING.
JWT=$(generate_jwt)
PRE_UPLOAD_BUILD_IDS=$(curl -s "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=$APP_ID&fields%5Bbuilds%5D=version&limit=20" \
  -H "Authorization: Bearer $JWT" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(','.join(b['id'] for b in d.get('data', [])))
except Exception:
    pass
" 2>/dev/null || echo "")

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

# Find the build we just uploaded by diffing the current build list
# against the pre-upload snapshot taken in §3. Whatever build ID is in
# the new list but not the old one is ours, regardless of which version
# number ASC assigned. Once we have an ID, wait until it's VALID.
# `|| echo ""` keeps the pipe from killing the script under `set -euo
# pipefail` when curl or python returns unparseable data.
for attempt in $(seq 1 20); do
  BUILD_ID=$(curl -s "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=$APP_ID&fields%5Bbuilds%5D=version,processingState,uploadedDate&limit=20" \
    -H "Authorization: Bearer $JWT" 2>/dev/null | PRE_IDS="$PRE_UPLOAD_BUILD_IDS" python3 -c "
import sys, os, json
try:
    pre = set(filter(None, os.environ.get('PRE_IDS', '').split(',')))
    d = json.load(sys.stdin)
    builds = d.get('data', [])
    new = [b for b in builds if b['id'] not in pre]
    new.sort(key=lambda b: b['attributes'].get('uploadedDate', ''), reverse=True)
    for b in new:
        if b['attributes'].get('processingState') == 'VALID':
            print(b['id'])
            print(b['attributes']['version'], file=sys.stderr)
            break
except Exception:
    pass
" 2>/tmp/shypquick-build-version || echo "")

  if [ -n "$BUILD_ID" ]; then
    ACTUAL_VERSION=$(cat /tmp/shypquick-build-version 2>/dev/null || echo "?")
    rm -f /tmp/shypquick-build-version
    if [ "$ACTUAL_VERSION" != "$NEW_BUILD" ] && [ "$ACTUAL_VERSION" != "?" ]; then
      echo "ℹ️  ASC stamped this upload as build $ACTUAL_VERSION (we asked for $NEW_BUILD)"
    fi
    echo "✅ Build processed: $BUILD_ID (build $ACTUAL_VERSION)"
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
    -H "Authorization: Bearer $JWT" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('data',{}).get('attributes',{}).get('betaReviewState','UNKNOWN'))
except Exception:
    print('UNKNOWN')
" 2>/dev/null || echo "UNKNOWN")

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
