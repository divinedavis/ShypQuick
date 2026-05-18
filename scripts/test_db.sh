#!/usr/bin/env bash
#
# ShypQuick — database gate tests.
#
# Runs supabase/tests/dispatch_gates_test.sql against the live project
# via the Supabase management API. The SQL uses plpgsql `assert`s; a
# failed assertion raises an exception, which the API returns as an
# error and this script reports as a failure.
#
# Requires $SUPABASE_ACCESS_TOKEN in the environment (auto-exported
# from the macOS keychain on this machine).
#
# Usage: ./scripts/test_db.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT_REF="ywacxbvqtofjglnmzkfi"
TEST_FILE="supabase/tests/dispatch_gates_test.sql"

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
    echo "❌ SUPABASE_ACCESS_TOKEN is not set"
    exit 1
fi

PAYLOAD=$(python3 -c 'import json,sys; print(json.dumps({"query": open(sys.argv[1]).read()}))' "$TEST_FILE")

RESPONSE=$(curl -s -X POST \
    "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: shypquick-dbtest/1.0" \
    -d "$PAYLOAD")

# A successful `do $$ ... $$` block returns an empty array.
if [[ "$RESPONSE" == "[]" ]]; then
    echo "✅ DB dispatch-gate tests passed"
    exit 0
fi

echo "❌ DB dispatch-gate tests FAILED"
echo "$RESPONSE"
exit 1
