#!/usr/bin/env bash
set -u

# Schema sync with workaround for stale singleton versioning ID.
# Runs inside the squidex-sync container.
# Kræver: SQ_URL, SQ_APP, SQ_CLIENT_ID, SQ_CLIENT_SECRET (fra container env)

dotnet tool run sq -- config add "$SQ_APP" "$SQ_CLIENT_ID" "$SQ_CLIENT_SECRET" --url "$SQ_URL" --use >/dev/null
dotnet tool run sq -- sync in -t schemas /ktk-config

SQ_TOKEN=$(curl -sf -X POST "$SQ_URL/identity-server/connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$SQ_CLIENT_ID&client_secret=$SQ_CLIENT_SECRET&scope=squidex-api" \
  | jq -r .access_token)

CURRENT_ID=$(curl -sf "$SQ_URL/api/content/$SQ_APP/versioning" \
  -H "Authorization: Bearer $SQ_TOKEN" \
  | jq -r ".items[0].id")

if [ -z "$CURRENT_ID" ] || [ "$CURRENT_ID" = "null" ]; then
  echo "❌ Kunne ikke hente versioning-id fra Squidex"
  exit 1
fi

TMP_DIR=$(mktemp -d)
mkdir -p "$TMP_DIR/ktk-config/contents/versioning" "$TMP_DIR/ktk-config/contents/release-notes"
cp /ktk-config/contents/versioning/singleton.json "$TMP_DIR/ktk-config/contents/versioning/singleton.json"
cp /ktk-config/contents/release-notes/items.json "$TMP_DIR/ktk-config/contents/release-notes/items.json"

jq --arg id "$CURRENT_ID" ".id = \$id" \
  "$TMP_DIR/ktk-config/contents/versioning/singleton.json" > "$TMP_DIR/singleton.json"
mv "$TMP_DIR/singleton.json" "$TMP_DIR/ktk-config/contents/versioning/singleton.json"

KTK_CONFIG_DIR="$TMP_DIR/ktk-config" \
SQ_URL="$SQ_URL" SQ_APP="$SQ_APP" \
SQ_CLIENT_ID="$SQ_CLIENT_ID" SQ_CLIENT_SECRET="$SQ_CLIENT_SECRET" \
bash /sync-versioning-content.sh --in
