#!/usr/bin/env sh

#Support for pushover.net's api. Push notification platform for multiple platforms

PUSHOVER_URI="https://api.pushover.net/1/messages.json"

pushover_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  PUSHOVER_TOKEN="${PUSHOVER_TOKEN:-$(_readaccountconf_mutable PUSHOVER_TOKEN)}"
  if [ -z "$PUSHOVER_TOKEN" ]; then
    PUSHOVER_TOKEN=""
    _err "You didn't specify a PushOver application token yet."
    return 1
  fi
  _saveaccountconf_mutable PUSHOVER_TOKEN "$PUSHOVER_TOKEN"

  PUSHOVER_USER="${PUSHOVER_USER:-$(_readaccountconf_mutable PUSHOVER_USER)}"
  if [ -z "$PUSHOVER_USER" ]; then
    PUSHOVER_USER=""
    _err "You didn't specify a PushOver UserKey yet."
    return 1
  fi
  _saveaccountconf_mutable PUSHOVER_USER "$PUSHOVER_USER"

# Specific device or devices by hostnames, joining multiples with a comma (such as device=iphone,nexus5)
  PUSHOVER_DEVICE="${PUSHOVER_DEVICE:-$(_readaccountconf_mutable PUSHOVER_DEVICE)}"
  if [ -z "$PUSHOVER_DEVICE" ]; then
    PUSHOVER_DEVICE=""
  fi
  _saveaccountconf_mutable PUSHOVER_DEVICE "$PUSHOVER_DEVICE"

# Lowest Priority (-2), Low Priority (-1), Normal Priority (0), High Priority (1)
  PUSHOVER_PRIORITY="${PUSHOVER_PRIORITY:-$(_readaccountconf_mutable PUSHOVER_PRIORITY)}"
  if [ -z "$PUSHOVER_PRIORITY" ]; then
    PUSHOVER_PRIORITY="0"
  fi
  _saveaccountconf_mutable PUSHOVER_PRIORITY "$PUSHOVER_PRIORITY"


  PUSHOVER_SOUND="${PUSHOVER_SOUND:-$(_readaccountconf_mutable PUSHOVER_SOUND)}"
  if [ -z "$PUSHOVER_SOUND" ]; then
    PUSHOVER_SOUND="" # Play default if not specified.
  fi
  _saveaccountconf_mutable PUSHOVER_SOUND "$PUSHOVER_SOUND"

  export _H1="Content-Type: application/json"
  _content="$(printf "*%s*\n" "$_content" | _json_encode)"
  _subject="$(printf "*%s*\n" "$_subject" | _json_encode)"
  _data="{\"token\": \"$PUSHOVER_TOKEN\",\"user\": \"$PUSHOVER_USER\",\"title\": \"$_subject\",\"message\": \"$_content\",\"sound\": \"$PUSHOVER_SOUND\", \"$

  response="" #just make shellcheck happy
  if _post "$_data" "$PUSHOVER_URI"; then
    if _contains "$response" "{\"status\":1"; then
      _info "PUSHOVER send sccess."
      return 0
    fi
  fi
  _err "PUSHOVER send error."
  _err "$response"
  return 1
}

