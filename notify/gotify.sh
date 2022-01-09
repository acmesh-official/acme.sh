#!/usr/bin/env sh

#Support Gotify

#GOTIFY_URL="https://gotify.example.com"
#GOTIFY_TOKEN="123456789ABCDEF"

#optional
#GOTIFY_PRIORITY=0

# subject  content statusCode
gotify_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  GOTIFY_URL="${GOTIFY_URL:-$(_readaccountconf_mutable GOTIFY_URL)}"
  if [ -z "$GOTIFY_URL" ]; then
    GOTIFY_URL=""
    _err "You didn't specify the gotify server url GOTIFY_URL."
    return 1
  fi
  _saveaccountconf_mutable GOTIFY_URL "$GOTIFY_URL"

  GOTIFY_TOKEN="${GOTIFY_TOKEN:-$(_readaccountconf_mutable GOTIFY_TOKEN)}"
  if [ -z "$GOTIFY_TOKEN" ]; then
    GOTIFY_TOKEN=""
    _err "You didn't specify the gotify token GOTIFY_TOKEN."
    return 1
  fi
  _saveaccountconf_mutable GOTIFY_TOKEN "$GOTIFY_TOKEN"

  GOTIFY_PRIORITY="${GOTIFY_PRIORITY:-$(_readaccountconf_mutable GOTIFY_PRIORITY)}"
  if [ -z "$GOTIFY_PRIORITY" ]; then
    GOTIFY_PRIORITY=0
  else
    _saveaccountconf_mutable GOTIFY_PRIORITY "$GOTIFY_PRIORITY"
  fi

  export _H1="X-Gotify-Key: ${GOTIFY_TOKEN}"
  export _H2="Content-Type: application/json"

  _content=$(echo "$_content" | _json_encode)
  _subject=$(echo "$_subject" | _json_encode)

  _data="{\"title\": \"${_subject}\", \"message\": \"${_content}\", \"priority\": ${GOTIFY_PRIORITY}}"

  response="$(_post "${_data}" "${GOTIFY_URL}/message" "" "POST" "application/json")"

  if [ "$?" != "0" ]; then
    _err "Failed to send message"
    _err "$response"
    return 1
  fi

  _debug2 response "$response"

  return 0
}
