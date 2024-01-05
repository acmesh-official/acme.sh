#!/usr/bin/env sh

#Support postmarkapp.com API (https://postmarkapp.com/developer/user-guide/sending-email/sending-with-api)

#POSTMARK_TOKEN=""
#POSTMARK_TO="xxxx@xxx.com"
#POSTMARK_FROM="xxxx@cccc.com"

postmark_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  POSTMARK_TOKEN="${POSTMARK_TOKEN:-$(_readaccountconf_mutable POSTMARK_TOKEN)}"
  if [ -z "$POSTMARK_TOKEN" ]; then
    POSTMARK_TOKEN=""
    _err "You didn't specify a POSTMARK api token POSTMARK_TOKEN yet ."
    _err "You can get yours from here https://account.postmarkapp.com"
    return 1
  fi
  _saveaccountconf_mutable POSTMARK_TOKEN "$POSTMARK_TOKEN"

  POSTMARK_TO="${POSTMARK_TO:-$(_readaccountconf_mutable POSTMARK_TO)}"
  if [ -z "$POSTMARK_TO" ]; then
    POSTMARK_TO=""
    _err "You didn't specify an email to POSTMARK_TO receive messages."
    return 1
  fi
  _saveaccountconf_mutable POSTMARK_TO "$POSTMARK_TO"

  POSTMARK_FROM="${POSTMARK_FROM:-$(_readaccountconf_mutable POSTMARK_FROM)}"
  if [ -z "$POSTMARK_FROM" ]; then
    POSTMARK_FROM=""
    _err "You didn't specify an email from POSTMARK_FROM receive messages."
    return 1
  fi
  _saveaccountconf_mutable POSTMARK_FROM "$POSTMARK_FROM"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  export _H3="X-Postmark-Server-Token: $POSTMARK_TOKEN"

  _content="$(echo "$_content" | _json_encode)"
  _data="{\"To\": \"$POSTMARK_TO\", \"From\": \"$POSTMARK_FROM\", \"Subject\": \"$_subject\", \"TextBody\": \"$_content\"}"
  if _post "$_data" "https://api.postmarkapp.com/email"; then
    # shellcheck disable=SC2154
    _message=$(printf "%s\n" "$response" | _lower_case | _egrep_o "\"message\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | head -n 1)
    if [ "$_message" = "ok" ]; then
      _info "postmark send success."
      return 0
    fi
  fi
  _err "postmark send error."
  _err "$response"
  return 1

}
