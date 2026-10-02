#!/usr/bin/env sh

#Support WAHA (WhatsApp HTTP API) - free, self-hosted WhatsApp API
#https://waha.devlike.pro/

#Required:
#WAHA_URL="http://localhost:3000"
#WAHA_CHAT_ID="1234567890@c.us"

#Optional:
#WAHA_API_KEY=""
#WAHA_SESSION="default"

waha_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  WAHA_URL="${WAHA_URL:-$(_readaccountconf_mutable WAHA_URL)}"
  if [ -z "$WAHA_URL" ]; then
    WAHA_URL=""
    _err "You didn't specify the WAHA server url WAHA_URL yet."
    _err "Example: export WAHA_URL=\"http://localhost:3000\""
    return 1
  fi
  _saveaccountconf_mutable WAHA_URL "$WAHA_URL"

  WAHA_CHAT_ID="${WAHA_CHAT_ID:-$(_readaccountconf_mutable WAHA_CHAT_ID)}"
  if [ -z "$WAHA_CHAT_ID" ]; then
    WAHA_CHAT_ID=""
    _err "You didn't specify the WhatsApp chat id WAHA_CHAT_ID yet."
    _err "Example: export WAHA_CHAT_ID=\"1234567890@c.us\""
    return 1
  fi
  _saveaccountconf_mutable WAHA_CHAT_ID "$WAHA_CHAT_ID"

  WAHA_API_KEY="${WAHA_API_KEY:-$(_readaccountconf_mutable WAHA_API_KEY)}"
  if [ "$WAHA_API_KEY" ]; then
    _saveaccountconf_mutable WAHA_API_KEY "$WAHA_API_KEY"
  fi

  WAHA_SESSION="${WAHA_SESSION:-$(_readaccountconf_mutable WAHA_SESSION)}"
  if [ -z "$WAHA_SESSION" ]; then
    WAHA_SESSION="default"
  else
    _saveaccountconf_mutable WAHA_SESSION "$WAHA_SESSION"
  fi

  _content=$(printf "*%s*\n%s" "$_subject" "$_content" | _json_encode)

  _data="{\"chatId\": \"$WAHA_CHAT_ID\", "
  _data="$_data\"text\": \"$_content\", "
  _data="$_data\"session\": \"$WAHA_SESSION\"}"

  _debug "_data" "$_data"

  if [ "$WAHA_API_KEY" ]; then
    export _H1="X-Api-Key: $WAHA_API_KEY"
  fi

  _waha_url="${WAHA_URL}/api/sendText"
  response="$(_post "$_data" "$_waha_url" "" "POST" "application/json")"

  if [ "$?" = "0" ] && _contains "$response" "\"id\""; then
    _info "waha send success."
    return 0
  fi
  _err "waha send error."
  _err "$response"
  return 1
}
