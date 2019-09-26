#!/usr/bin/env sh

#Support ifttt.com webhooks api

#IFTTT_API_KEY="xxxx"
#IFTTT_EVENT_NAME="yyyy"

#IFTTT_SUBJECT_KEY="value1|value2|value3"      #optional, use "value1" as default
#IFTTT_CONTENT_KEY="value1|value2|value3"      #optional, use "value2" as default

_IFTTT_AVAIL_MSG_KEYS="value1,value2,value3"

# subject  content statusCode
ifttt_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  IFTTT_API_KEY="${IFTTT_API_KEY:-$(_readaccountconf_mutable IFTTT_API_KEY)}"
  if [ -z "$IFTTT_API_KEY" ]; then
    IFTTT_API_KEY=""
    _err "You didn't specify a ifttt webhooks api key IFTTT_API_KEY yet."
    _err "You can get yours from https://ifttt.com"
    return 1
  fi
  _saveaccountconf_mutable IFTTT_API_KEY "$IFTTT_API_KEY"

  IFTTT_EVENT_NAME="${IFTTT_EVENT_NAME:-$(_readaccountconf_mutable IFTTT_EVENT_NAME)}"
  if [ -z "$IFTTT_EVENT_NAME" ]; then
    IFTTT_EVENT_NAME=""
    _err "You didn't specify a ifttt webhooks event name IFTTT_EVENT_NAME yet."
    return 1
  fi
  _saveaccountconf_mutable IFTTT_EVENT_NAME "$IFTTT_EVENT_NAME"

  IFTTT_SUBJECT_KEY="${IFTTT_SUBJECT_KEY:-$(_readaccountconf_mutable IFTTT_SUBJECT_KEY)}"
  if [ -z "$IFTTT_SUBJECT_KEY" ]; then
    IFTTT_SUBJECT_KEY="value1"
    _info "The IFTTT_SUBJECT_KEY is not set, so use the default value1 as key."
  elif ! _hasfield "$_IFTTT_AVAIL_MSG_KEYS" "$IFTTT_SUBJECT_KEY"; then
    _err "The IFTTT_SUBJECT_KEY \"$IFTTT_SUBJECT_KEY\" is not available, should be one of $_IFTTT_AVAIL_MSG_KEYS"
    IFTTT_SUBJECT_KEY=""
    return 1
  else
    _saveaccountconf_mutable IFTTT_SUBJECT_KEY "$IFTTT_SUBJECT_KEY"
  fi

  IFTTT_CONTENT_KEY="${IFTTT_CONTENT_KEY:-$(_readaccountconf_mutable IFTTT_CONTENT_KEY)}"
  if [ -z "$IFTTT_CONTENT_KEY" ]; then
    IFTTT_CONTENT_KEY="value2"
    _info "The IFTTT_CONTENT_KEY is not set, so use the default value2 as key."
  elif ! _hasfield "$_IFTTT_AVAIL_MSG_KEYS" "$IFTTT_CONTENT_KEY"; then
    _err "The IFTTT_CONTENT_KEY \"$IFTTT_CONTENT_KEY\" is not available, should be one of $_IFTTT_AVAIL_MSG_KEYS"
    IFTTT_CONTENT_KEY=""
    return 1
  else
    _saveaccountconf_mutable IFTTT_CONTENT_KEY "$IFTTT_CONTENT_KEY"
  fi

  if [ "$IFTTT_SUBJECT_KEY" = "$IFTTT_CONTENT_KEY" ]; then
    IFTTT_SUBJECT_KEY=""
    IFTTT_CONTENT_KEY=""
    _err "The IFTTT_SUBJECT_KEY must not be same as IFTTT_CONTENT_KEY."
    return 1
  fi

  IFTTT_API_URL="https://maker.ifttt.com/trigger/$IFTTT_EVENT_NAME/with/key/$IFTTT_API_KEY"

  _content=$(echo "$_content" | _json_encode)
  _subject=$(echo "$_subject" | _json_encode)
  _data="{\"$IFTTT_SUBJECT_KEY\": \"$_subject\", \"$IFTTT_CONTENT_KEY\": \"$_content\"}"

  response="$(_post "$_data" "$IFTTT_API_URL" "" "POST" "application/json")"

  if [ "$?" = "0" ] && _contains "$response" "Congratulations"; then
    _info "IFTTT webhooks event fired success."
    return 0
  fi

  _err "IFTTT webhooks event fired error."
  _err "$response"
  return 1
}
