#!/usr/bin/env sh

# Support Schmoogle Gchat webhooks
# start with exporting your Spaces webhook with - export GCHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/xxxxxxxxxxxx"
# add the hook with - acme.sh --set-notify --notify-hook gchat

gchat_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  GCHAT_WEBHOOK_URL="${GCHAT_WEBHOOK_URL:-$(_readaccountconf_mutable GCHAT_WEBHOOK_URL)}"
  if [ -z "$GCHAT_WEBHOOK_URL" ]; then
    GCHAT_WEBHOOK_URL=""
    _err "You didn't specify a Gchat webhook url. export GCHAT_WEBHOOK_URL=\"https://chat.googleapis.com/v1/spaces/xxxxxxx\""
    return 1
  fi
  _saveaccountconf_mutable GCHAT_WEBHOOK_URL "$GCHAT_WEBHOOK_URL"

  export _H1="Content-Type: application/json"

  _content="$(printf "*%s*\n%s" "$_subject" "$_content" | _json_encode)"
  _data="{\"text\": \"$_content\"}"

  if _post "$_data" "$GCHAT_WEBHOOK_URL"; then
    if [ "$?" = "0" ]; then
      _info "gchat send success."
      return 0
    fi
  fi
  _err "gchat send error."
  _err "$response"
  return 1
}
