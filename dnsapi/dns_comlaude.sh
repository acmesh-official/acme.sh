#!/usr/bin/env bash

# ===== CONFIG =====
COMLAUDE_API="https://api.comlaude.com"

########## AUTH ##########

_comlaude_auth() {
  if [ -n "${COMLAUDE_ACCESS_TOKEN:-}" ]; then
    return 0
  fi

  if [ -z "${COMLAUDE_USERNAME:-}" ] || [ -z "${COMLAUDE_PASSWORD:-}" ] || [ -z "${COMLAUDE_API_KEY:-}" ]; then
    echo "❌ Missing COMLAUDE credentials"
    return 1
  fi

  echo "🔐 ComLaude auth..."

  AUTH_RESPONSE=$(curl -s -X POST "$COMLAUDE_API/api_login" \
    -H "Content-Type: application/json" \
    -d "{
      \"username\": \"$COMLAUDE_USERNAME\",
      \"password\": \"$COMLAUDE_PASSWORD\",
      \"api_key\": \"$COMLAUDE_API_KEY\"
    }")

  COMLAUDE_ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.data.access_token')

  if [ "$COMLAUDE_ACCESS_TOKEN" = "null" ] || [ -z "$COMLAUDE_ACCESS_TOKEN" ]; then
    echo "❌ Auth failed"
    echo "$AUTH_RESPONSE" | jq
    return 1
  fi

  export COMLAUDE_ACCESS_TOKEN
}

########## DOMAIN RESOLUTION ##########

_comlaude_get_root() {
  domain="$1"

  i=1
  p=1

  while true; do
    d=$(echo "$domain" | cut -d . -f $i-100)
    if [ -z "$d" ]; then
      return 1
    fi

    echo "🔎 Checking domain: $d"

    DOMAIN_RESPONSE=$(curl -g -s \
      -H "Authorization: Bearer $COMLAUDE_ACCESS_TOKEN" \
      "$COMLAUDE_API/groups/$COMLAUDE_GROUP_ID/domains?filter%5Bname%5D=$d&fields=id,name,active_zone")

    DOMAIN_ID=$(echo "$DOMAIN_RESPONSE" | jq -r '.data[0].id')
    ZONE_ID=$(echo "$DOMAIN_RESPONSE" | jq -r '.data[0].active_zone.id')

    if [ "$DOMAIN_ID" != "null" ] && [ -n "$DOMAIN_ID" ]; then
      _domain_id="$DOMAIN_ID"
      _zone_id="$ZONE_ID"
      _domain="$d"
      return 0
    fi

    i=$((i+1))
  done
}

########## ADD TXT ##########

dns_comlaude_add() {
  fulldomain="$1"
  txtvalue="$2"

  echo "➕ Adding TXT for $fulldomain"

  _comlaude_auth || return 1
  _comlaude_get_root "$fulldomain" || return 1

  subdomain="${fulldomain%.$_domain}"

  echo "📌 Root domain: $_domain"
  echo "📌 Subdomain: $subdomain"

  # ✅ ===== CHECK EXISTING TXT =====
  echo "🔎 Checking if TXT already exists..."

  EXISTING=$(curl -s \
    -H "Authorization: Bearer $COMLAUDE_ACCESS_TOKEN" \
    "$COMLAUDE_API/groups/$COMLAUDE_GROUP_ID/zones/$_zone_id/records" \
    | jq -r \
    ".data[] | select(.type==\"TXT\" and .name==\"$fulldomain\" and .value==\"$txtvalue\") | .id")

  if [ -n "$EXISTING" ]; then
    echo "✅ TXT already exists, skipping"
    return 0
  fi
  # ✅ ===== END CHECK =====

  RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $COMLAUDE_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    "$COMLAUDE_API/groups/$COMLAUDE_GROUP_ID/zones/$_zone_id/records" \
    -d "{
      \"type\": \"TXT\",
      \"name\": \"$fulldomain\",
      \"value\": \"$txtvalue\",
      \"ttl\": 60
    }")

  echo "$RESPONSE" | jq .

  return 0
}

########## REMOVE TXT ##########

dns_comlaude_rm() {
  fulldomain="$1"
  txtvalue="$2"

  echo "➖ Removing TXT for $fulldomain"

  _comlaude_auth || return 1
  _comlaude_get_root "$fulldomain" || return 1

  RECORDS=$(curl -s \
    -H "Authorization: Bearer $COMLAUDE_ACCESS_TOKEN" \
    "$COMLAUDE_API/groups/$COMLAUDE_GROUP_ID/zones/$_zone_id/records")

  RECORD_ID=$(echo "$RECORDS" | jq -r \
    ".data[] | select(.type==\"TXT\" and .name==\"$fulldomain\" and .value==\"$txtvalue\") | .id")

  if [ -z "$RECORD_ID" ]; then
    echo "⚠️ Record not found"
    return 0
  fi

  curl -s -X DELETE \
    -H "Authorization: Bearer $COMLAUDE_ACCESS_TOKEN" \
    "$COMLAUDE_API/groups/$COMLAUDE_GROUP_ID/zones/$_zone_id/records/$RECORD_ID"

  echo "✅ TXT removed"

  return 0
}
