#!/usr/bin/env sh

#Support for pushover.net's api. Push notification platform for multiple platforms
#PUSHOVER_TOKEN="" Required, pushover application token
#PUSHOVER_USER="" Required, pushover userkey
#PUSHOVER_DEVICE="" Optional, Specific device or devices by hostnames, joining multiples with a comma (such as device=iphone,nexus5)
#PUSHOVER_PRIORITY="" Optional, Lowest Priority (-2), Low Priority (-1), Normal Priority (0), High Priority (1)

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

  PUSHOVER_DEVICE="${PUSHOVER_DEVICE:-$(_readaccountconf_mutable PUSHOVER_DEVICE)}"
  if [ "$PUSHOVER_DEVICE" ]; then
    _saveaccountconf_mutable PUSHOVER_DEVICE "$PUSHOVER_DEVICE"
  fi

  PUSHOVER_PRIORITY="${PUSHOVER_PRIORITY:-$(_readaccountconf_mutable PUSHOVER_PRIORITY)}"
  if [ "$PUSHOVER_PRIORITY" ]; then
    _saveaccountconf_mutable PUSHOVER_PRIORITY "$PUSHOVER_PRIORITY"
  fi

  PUSHOVER_SOUND="${PUSHOVER_SOUND:-$(_readaccountconf_mutable PUSHOVER_SOUND)}"
  if [ "$PUSHOVER_SOUND" ]; then
    _saveaccountconf_mutable PUSHOVER_SOUND "$PUSHOVER_SOUND"
  fi

  export _H1="Content-Type: application/json"
  _content="$(printf "*%s*\n" "$_content" | _json_encode)"
  _subject="$(printf "*%s*\n" "$_subject" | _json_encode)"
  _data="{\"token\": \"$PUSHOVER_TOKEN\",\"user\": \"$PUSHOVER_USER\",\"title\": \"$_subject\",\"message\": \"$_content\",\"sound\": \"$PUSHOVER_SOUND\", \"device\": \"$PUSHOVER_DEVICE\", \"priority\": \"$PUSHOVER_PRIORITY\"}"

  response="$(_post "$_data" "$PUSHOVER_URI")"

  if [ "$?" = "0" ] && _contains "$response" "{\"status\":1"; then
    _info "PUSHOVER send success."
    return 0
  fi

  _err "PUSHOVER send error."
  _err "$response"
  return 1
}
