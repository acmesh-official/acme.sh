#!/usr/bin/bash

#Support http webhooks api

#HTTP_WEBHOOK="xxxx"

# subject content statusCode
http_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  HTTP_WEBHOOK="${HTTP_WEBHOOK:-$(_readaccountconf_mutable HTTP_WEBHOOK)}"
  if [ -z "$HTTP_WEBHOOK" ]; then
    HTTP_WEBHOOK=""
    _err "You didn't specify a http webhook HTTP_WEBHOOK yet."
    return 1
  fi
  _saveaccountconf_mutable HTTP_WEBHOOK "$HTTP_WEBHOOK"

  _content=$(echo "$_content" | _json_encode)
  _subject=$(echo "$_subject" | _json_encode)
  _data="{\"subject\": \"$_subject\", \"content\": \"$_content\", \"status\": $_statusCode}"

  response="$(_post "$_data" "$HTTP_WEBHOOK" "" "POST" "application/json")"

  if [ "$?" = "0" ]; then
    _info "http webhooks event fired success."
    return 0
  fi

  _err "http webhooks event fired error."
  _err "$response"
  return 1
}
