#!/usr/bin/env sh

#Support SENDGRID.com api

#SENDGRID_API_KEY=""
#SENDGRID_TO="xxxx@xxx.com"
#SENDGRID_FROM="xxxx@cccc.com"

sendgrid_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  SENDGRID_API_KEY="${SENDGRID_API_KEY:-$(_readaccountconf_mutable SENDGRID_API_KEY)}"
  if [ -z "$SENDGRID_API_KEY" ]; then
    SENDGRID_API_KEY=""
    _err "You didn't specify a sendgrid api key SENDGRID_API_KEY yet ."
    _err "You can get yours from here https://sendgrid.com"
    return 1
  fi
  _saveaccountconf_mutable SENDGRID_API_KEY "$SENDGRID_API_KEY"

  SENDGRID_TO="${SENDGRID_TO:-$(_readaccountconf_mutable SENDGRID_TO)}"
  if [ -z "$SENDGRID_TO" ]; then
    SENDGRID_TO=""
    _err "You didn't specify an email to SENDGRID_TO receive messages."
    return 1
  fi
  _saveaccountconf_mutable SENDGRID_TO "$SENDGRID_TO"

  SENDGRID_FROM="${SENDGRID_FROM:-$(_readaccountconf_mutable SENDGRID_FROM)}"
  if [ -z "$SENDGRID_FROM" ]; then
    SENDGRID_FROM=""
    _err "You didn't specify an email to SENDGRID_FROM receive messages."
    return 1
  fi
  _saveaccountconf_mutable SENDGRID_FROM "$SENDGRID_FROM"

  export _H1="Authorization: Bearer $SENDGRID_API_KEY"
  export _H2="Content-Type: application/json"

  _content="$(echo "$_content" | _json_encode)"
  _data="{\"personalizations\": [{\"to\": [{\"email\": \"$SENDGRID_TO\"}]}],\"from\": {\"email\": \"$SENDGRID_FROM\"},\"subject\": \"$_subject\",\"content\": [{\"type\": \"text/plain\", \"value\": \"$_content\"}]}"
  response="$(_post "$_data" "https://api.sendgrid.com/v3/mail/send")"

  if [ "$?" = "0" ] && [ -z "$response" ]; then
    _info "sendgrid send sccess."
    return 0
  fi

  _err "sendgrid send error."
  _err "$response"
  return 1

}
