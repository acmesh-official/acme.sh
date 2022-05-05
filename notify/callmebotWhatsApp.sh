#!/usr/bin/bash

#Support CallMeBot Whatsapp webhooks

#CallMeBot_Phone_No=""
#CallMeBot_apikey=""

callmebotWhatsApp_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  CallMeBot_Phone_No="${CallMeBot_Phone_No:-$(_readaccountconf_mutable CallMeBot_Phone_No)}"
  if [ -z "$CallMeBot_Phone_No" ]; then
    CallMeBot_Phone_No=""
    _err "You didn't specify a Slack webhook url CallMeBot_Phone_No yet."
    return 1
  fi
  _saveaccountconf_mutable CallMeBot_Phone_No "$CallMeBot_Phone_No"

  CallMeBot_apikey="${CallMeBot_apikey:-$(_readaccountconf_mutable CallMeBot_apikey)}"
  if [ -n "$CallMeBot_apikey" ]; then
    _saveaccountconf_mutable CallMeBot_apikey "$CallMeBot_apikey"
  fi
  
  _waUrl="https://api.callmebot.com/whatsapp.php"
  
  _Phone_No="$(printf "%s" "$CallMeBot_Phone_No" | _url_encode)"
  _apikey="$(printf "%s" "$CallMeBot_apikey" | _url_encode)"
  _message="$(printf "$CQHTTP_CUSTOM_MSGHEAD *%s*\\n%s" "$_subject" "$_content" | _url_encode)"
  
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