#!/usr/bin/env sh

#Support for pushbullet.com's api. Push notification, notification sync and message platform for multiple platforms
#PUSHBULLET_TOKEN="" Required, pushbullet application token
#PUSHBULLET_DEVICE="" Optional, Specific device, ignore to send to all devices

PUSHBULLET_URI="https://api.pushbullet.com/v2/pushes"
pushbullet_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  PUSHBULLET_TOKEN="${PUSHBULLET_TOKEN:-$(_readaccountconf_mutable PUSHBULLET_TOKEN)}"
  if [ -z "$PUSHBULLET_TOKEN" ]; then
    PUSHBULLET_TOKEN=""
    _err "You didn't specify a Pushbullet application token yet."
    return 1
  fi
  _saveaccountconf_mutable PUSHBULLET_TOKEN "$PUSHBULLET_TOKEN"

  PUSHBULLET_DEVICE="${PUSHBULLET_DEVICE:-$(_readaccountconf_mutable PUSHBULLET_DEVICE)}"
  if [ -z "$PUSHBULLET_DEVICE" ]; then
    _clearaccountconf_mutable PUSHBULLET_DEVICE
  else
    _saveaccountconf_mutable PUSHBULLET_DEVICE "$PUSHBULLET_DEVICE"
  fi

  export _H1="Content-Type: application/json"
  export _H2="Access-Token: ${PUSHBULLET_TOKEN}"
  _content="$(printf "*%s*\n" "$_content" | _json_encode)"
  _subject="$(printf "*%s*\n" "$_subject" | _json_encode)"
  _data="{\"type\": \"note\",\"title\": \"${_subject}\",\"body\": \"${_content}\",\"device_iden\": \"${PUSHBULLET_DEVICE}\"}"
  response="$(_post "$_data" "$PUSHBULLET_URI")"

  if [ "$?" != "0" ] || _contains "$response" "\"error_code\""; then
    _err "PUSHBULLET send error."
    _err "$response"
    return 1
  fi

  _info "PUSHBULLET send success."
  return 0
}
