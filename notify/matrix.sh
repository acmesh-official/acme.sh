#!/usr/bin/env sh

#Support Matrix API

#MATRIX_SERVER_URL=""
#MATRIX_API_TOKEN=""
#MATRIX_ROOM_ID=""

matrix_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  MATRIX_SERVER_URL="${MATRIX_SERVER_URL:-$(_readaccountconf_mutable MATRIX_SERVER_URL)}"
  if [ -z "$MATRIX_SERVER_URL" ]; then
    MATRIX_SERVER_URL=""
    _err "You didn't specify a Matrix homeserver URL MATRIX_SERVER_URL yet."
    return 1
  fi
  _saveaccountconf_mutable MATRIX_SERVER_URL "$MATRIX_SERVER_URL"

  MATRIX_API_TOKEN="${MATRIX_API_TOKEN:-$(_readaccountconf_mutable MATRIX_API_TOKEN)}"
  if [ -z "$MATRIX_API_TOKEN" ]; then
    MATRIX_API_TOKEN=""
    _err "You didn't specify a Matrix private token MATRIX_API_TOKEN yet."
    return 1
  fi
  _saveaccountconf_mutable MATRIX_API_TOKEN "$MATRIX_API_TOKEN"

  MATRIX_ROOM_ID="${MATRIX_ROOM_ID:-$(_readaccountconf_mutable MATRIX_ROOM_ID)}"
  if [ -z "$MATRIX_ROOM_ID" ]; then
    MATRIX_ROOM_ID=""
    _err "You didn't specify a Matrix room ID MATRIX_ROOM_ID yet."
    return 1
  fi
  _saveaccountconf_mutable MATRIX_ROOM_ID "$MATRIX_ROOM_ID"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  export _H3="Authorization: Bearer $MATRIX_API_TOKEN"

  _content="$(printf "*%s*\n%s" "$_subject" "$_content" | _json_encode)"
  _data="{\"msgtype\": \"m.text\", \"body\": \"$_content\"}"
  if _post "$_data" "$MATRIX_SERVER_URL/_matrix/client/r0/rooms/$MATRIX_ROOM_ID/send/m.room.message"; then
    # shellcheck disable=SC2154
    if _contains "$response" "event_id"; then
      _info "matrix send success."
      return 0
    fi
  fi
  _err "matrix send error."
  _err "$response"
  return 1
}
