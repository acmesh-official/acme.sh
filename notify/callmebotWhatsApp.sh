#!/usr/bin/env sh

#Support CallMeBot Whatsapp webhooks

#CALLMEBOT_YOUR_PHONE_NO=""
#CALLMEBOT_API_KEY=""

callmebotWhatsApp_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  CALLMEBOT_YOUR_PHONE_NO="${CALLMEBOT_YOUR_PHONE_NO:-$(_readaccountconf_mutable CALLMEBOT_YOUR_PHONE_NO)}"
  if [ -z "$CALLMEBOT_YOUR_PHONE_NO" ]; then
    CALLMEBOT_YOUR_PHONE_NO=""
    _err "You didn't specify a Slack webhook url CALLMEBOT_YOUR_PHONE_NO yet."
    return 1
  fi
  _saveaccountconf_mutable CALLMEBOT_YOUR_PHONE_NO "$CALLMEBOT_YOUR_PHONE_NO"

  CALLMEBOT_API_KEY="${CALLMEBOT_API_KEY:-$(_readaccountconf_mutable CALLMEBOT_API_KEY)}"
  if [ "$CALLMEBOT_API_KEY" ]; then
    _saveaccountconf_mutable CALLMEBOT_API_KEY "$CALLMEBOT_API_KEY"
  fi

  _waUrl="https://api.callmebot.com/whatsapp.php"

  _Phone_No="$(printf "%s" "$CALLMEBOT_YOUR_PHONE_NO" | _url_encode)"
  _apikey="$(printf "%s" "$CALLMEBOT_API_KEY" | _url_encode)"
  _message="$(printf "*%s*\\n%s" "$_subject" "$_content" | _url_encode)"

  _finalUrl="$_waUrl?phone=$_Phone_No&apikey=$_apikey&text=$_message"
  response="$(_get "$_finalUrl")"

  if [ "$?" = "0" ] && _contains ".<p><b>Message queued.</b> You will receive it in a few seconds."; then
    _info "wa send success."
    return 0
  fi
  _err "wa send error."
  _debug "URL" "$_finalUrl"
  _debug "Response" "$response"
  return 1
}
