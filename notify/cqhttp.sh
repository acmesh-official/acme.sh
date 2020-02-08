#!/usr/bin/env sh

#Support for CQHTTP api. Push notification on CoolQ
#CQHTTP_TOKEN="" Recommended to be not empty, QQ application token
#CQHTTP_USER="" Required, QQ receiver ID
#CQHTTP_APIROOT="" Required, CQHTTP Server URL (without slash suffix)
#CQHTTP_CUSTOM_MSGHEAD="" Optional, custom message header

CQHTTP_APIPATH="/send_private_msg"

cqhttp_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  CQHTTP_TOKEN="${CQHTTP_TOKEN:-$(_readaccountconf_mutable CQHTTP_TOKEN)}"
  if [ -z "$CQHTTP_TOKEN" ]; then
    CQHTTP_TOKEN=""
    _info "You didn't specify a CQHTTP application token yet, which is unsafe. Assuming it to be empty."
  else
    _saveaccountconf_mutable CQHTTP_TOKEN "$CQHTTP_TOKEN"
  fi

  CQHTTP_USER="${CQHTTP_USER:-$(_readaccountconf_mutable CQHTTP_USER)}"
  if [ -z "$CQHTTP_USER" ]; then
    CQHTTP_USER=""
    _err "You didn't specify a QQ user yet."
    return 1
  fi
  _saveaccountconf_mutable CQHTTP_USER "$CQHTTP_USER"

  CQHTTP_APIROOT="${CQHTTP_APIROOT:-$(_readaccountconf_mutable CQHTTP_APIROOT)}"
  if [ -z "$CQHTTP_APIROOT" ]; then
    CQHTTP_APIROOT=""
    _err "You didn't specify the API root yet."
    return 1
  fi
  _saveaccountconf_mutable CQHTTP_APIROOT "$CQHTTP_APIROOT"

  CQHTTP_CUSTOM_MSGHEAD="${CQHTTP_CUSTOM_MSGHEAD:-$(_readaccountconf_mutable CQHTTP_CUSTOM_MSGHEAD)}"
  if [ -z "$CQHTTP_CUSTOM_MSGHEAD" ]; then
    CQHTTP_CUSTOM_MSGHEAD="A message from acme.sh:"
  else
    _saveaccountconf_mutable CQHTTP_CUSTOM_MSGHEAD "$CQHTTP_CUSTOM_MSGHEAD"
  fi

  _access_token="$(printf "%s" "$CQHTTP_TOKEN" | _url_encode)"
  _user_id="$(printf "%s" "$CQHTTP_USER" | _url_encode)"
  _message="$(printf "$CQHTTP_CUSTOM_MSGHEAD %s\\n%s" "$_subject" "$_content" | _url_encode)"

  _finalUrl="$CQHTTP_APIROOT$CQHTTP_APIPATH?access_token=$_access_token&user_id=$_user_id&message=$_message"
  response="$(_get "$_finalUrl")"

  if [ "$?" = "0" ] && _contains "$response" "\"retcode\":0,\"status\":\"ok\""; then
    _info "QQ send success."
    return 0
  fi

  _err "QQ send error."
  _debug "URL" "$_finalUrl"
  _debug "Response" "$response"
  return 1
}
