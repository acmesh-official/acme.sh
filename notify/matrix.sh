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

  _h1="$_H1"
  _h2="$_H2"
  _h3="$_H3"
  _h4="$_H4"
  _h5="$_H5"

  _H1="Accept: application/json"
  _H2="Content-Type: application/json"
  _H3="Authorization: Bearer $MATRIX_API_TOKEN"
  unset _H4
  unset _H5

  _content="$(printf "*%s*\n%s" "$_subject" "$_content" | _json_encode)"
  _data="{\"msgtype\": \"m.text\", \"body\": \"$_content\"}"

  _post "$_data" "$MATRIX_SERVER_URL/_matrix/client/r0/rooms/$MATRIX_ROOM_ID/send/m.room.message"

  _H1="$_h1"
  _H2="$_h2"
  _H3="$_h3"
  _H4="$_h4"
  _H5="$_h5"

  # shellcheck disable=SC2154
  if _contains "$response" "event_id"; then
    _info "matrix send success."
    return 0
  fi

  _err "matrix send error."
  _err "$response"
  return 1
}
