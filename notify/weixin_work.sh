#!/usr/bin/env sh

#Support weixin work webhooks api

#WEIXIN_WORK_WEBHOOK="xxxx"

#optional
#WEIXIN_WORK_KEYWORD="yyyy"

#`WEIXIN_WORK_SIGNING_KEY`="SEC08ffdbd403cbc3fc8a65xxxxxxxxxxxxxxxxxxxx"

# subject  content statusCode
weixin_work_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  WEIXIN_WORK_WEBHOOK="${WEIXIN_WORK_WEBHOOK:-$(_readaccountconf_mutable WEIXIN_WORK_WEBHOOK)}"
  if [ -z "$WEIXIN_WORK_WEBHOOK" ]; then
    WEIXIN_WORK_WEBHOOK=""
    _err "You didn't specify a weixin_work webhooks WEIXIN_WORK_WEBHOOK yet."
    _err "You can get yours from https://work.weixin.qq.com/api/doc/90000/90136/91770"
    return 1
  fi
  _saveaccountconf_mutable WEIXIN_WORK_WEBHOOK "$WEIXIN_WORK_WEBHOOK"

  WEIXIN_WORK_KEYWORD="${WEIXIN_WORK_KEYWORD:-$(_readaccountconf_mutable WEIXIN_WORK_KEYWORD)}"
  if [ "$WEIXIN_WORK_KEYWORD" ]; then
    _saveaccountconf_mutable WEIXIN_WORK_KEYWORD "$WEIXIN_WORK_KEYWORD"
  fi

  _content=$(echo "$_content" | _json_encode)
  _subject=$(echo "$_subject" | _json_encode)
  _data="{\"msgtype\": \"text\", \"text\": {\"content\": \"[$WEIXIN_WORK_KEYWORD]\n$_subject\n$_content\"}}"

  response="$(_post "$_data" "$WEIXIN_WORK_WEBHOOK" "" "POST" "application/json")"

  if [ "$?" = "0" ] && _contains "$response" "errmsg\":\"ok"; then
    _info "weixin_work webhooks event fired success."
    return 0
  fi

  _err "weixin_work webhooks event fired error."
  _err "$response"
  return 1
}
