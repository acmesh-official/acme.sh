#!/usr/bin/env sh

#Support feishu webhooks api

#required
#FEISHU_WEBHOOK="xxxx"

#optional
#FEISHU_KEYWORD="yyyy"

# subject content statusCode
feishu_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  FEISHU_WEBHOOK="${FEISHU_WEBHOOK:-$(_readaccountconf_mutable FEISHU_WEBHOOK)}"
  if [ -z "$FEISHU_WEBHOOK" ]; then
    FEISHU_WEBHOOK=""
    _err "You didn't specify a feishu webhooks FEISHU_WEBHOOK yet."
    _err "You can get yours from https://www.feishu.cn"
    return 1
  fi
  _saveaccountconf_mutable FEISHU_WEBHOOK "$FEISHU_WEBHOOK"

  FEISHU_KEYWORD="${FEISHU_KEYWORD:-$(_readaccountconf_mutable FEISHU_KEYWORD)}"
  if [ "$FEISHU_KEYWORD" ]; then
    _saveaccountconf_mutable FEISHU_KEYWORD "$FEISHU_KEYWORD"
  fi

  _content=$(echo "$_content" | _json_encode)
  _subject=$(echo "$_subject" | _json_encode)
  _data="{\"msg_type\": \"text\", \"content\": {\"text\": \"[$FEISHU_KEYWORD]\n$_subject\n$_content\"}}"

  response="$(_post "$_data" "$FEISHU_WEBHOOK" "" "POST" "application/json")"

  if [ "$?" = "0" ] && _contains "$response" "StatusCode\":0"; then
    _info "feishu webhooks event fired success."
    return 0
  fi

  _err "feishu webhooks event fired error."
  _err "$response"
  return 1
}
