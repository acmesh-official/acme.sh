#!/usr/bin/env sh

#Support dingtalk webhooks api

#DINGTALK_WEBHOOK="xxxx"

#optional
#DINGTALK_KEYWORD="yyyy"

#DINGTALK_SIGNING_KEY="SEC08ffdbd403cbc3fc8a65xxxxxxxxxxxxxxxxxxxx"

# subject  content statusCode
dingtalk_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  DINGTALK_WEBHOOK="${DINGTALK_WEBHOOK:-$(_readaccountconf_mutable DINGTALK_WEBHOOK)}"
  if [ -z "$DINGTALK_WEBHOOK" ]; then
    DINGTALK_WEBHOOK=""
    _err "You didn't specify a dingtalk webhooks DINGTALK_WEBHOOK yet."
    _err "You can get yours from https://dingtalk.com"
    return 1
  fi
  _saveaccountconf_mutable DINGTALK_WEBHOOK "$DINGTALK_WEBHOOK"

  DINGTALK_KEYWORD="${DINGTALK_KEYWORD:-$(_readaccountconf_mutable DINGTALK_KEYWORD)}"
  if [ "$DINGTALK_KEYWORD" ]; then
    _saveaccountconf_mutable DINGTALK_KEYWORD "$DINGTALK_KEYWORD"
  fi

  #  DINGTALK_SIGNING_KEY="${DINGTALK_SIGNING_KEY:-$(_readaccountconf_mutable DINGTALK_SIGNING_KEY)}"
  #  if [ -z "$DINGTALK_SIGNING_KEY" ]; then
  #    DINGTALK_SIGNING_KEY="value1"
  #    _info "The DINGTALK_SIGNING_KEY is not set, so use the default value1 as key."
  #  elif ! _hasfield "$_IFTTT_AVAIL_MSG_KEYS" "$DINGTALK_SIGNING_KEY"; then
  #    _err "The DINGTALK_SIGNING_KEY \"$DINGTALK_SIGNING_KEY\" is not available, should be one of $_IFTTT_AVAIL_MSG_KEYS"
  #    DINGTALK_SIGNING_KEY=""
  #    return 1
  #  else
  #    _saveaccountconf_mutable DINGTALK_SIGNING_KEY "$DINGTALK_SIGNING_KEY"
  #  fi

  #  if [ "$DINGTALK_SIGNING_KEY" = "$IFTTT_CONTENT_KEY" ]; then
  #    DINGTALK_SIGNING_KEY=""
  #    IFTTT_CONTENT_KEY=""
  #    _err "The DINGTALK_SIGNING_KEY must not be same as IFTTT_CONTENT_KEY."
  #    return 1
  #  fi

  _content=$(echo "$_content" | _json_encode)
  _subject=$(echo "$_subject" | _json_encode)
  _data="{\"msgtype\": \"text\", \"text\": {\"content\": \"[$DINGTALK_KEYWORD]\n$_subject\n$_content\"}}"

  response="$(_post "$_data" "$DINGTALK_WEBHOOK" "" "POST" "application/json")"

  if [ "$?" = "0" ] && _contains "$response" "errmsg\":\"ok"; then
    _info "dingtalk webhooks event fired success."
    return 0
  fi

  _err "dingtalk webhooks event fired error."
  _err "$response"
  return 1
}
