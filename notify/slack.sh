#!/usr/bin/env sh

#Support Slack webhooks

#SLACK_WEBHOOK_URL=""

slack_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-$(_readaccountconf_mutable SLACK_WEBHOOK_URL)}"
  if [ -z "$SLACK_WEBHOOK_URL" ]; then
    SLACK_WEBHOOK_URL=""
    _err "You didn't specify a Slack webhook url SLACK_WEBHOOK_URL yet."
    return 1
  fi
  _saveaccountconf_mutable SLACK_WEBHOOK_URL "$SLACK_WEBHOOK_URL"

  export _H1="Content-Type: application/json"

  _content="$(echo "$_subject: $_content" | _json_encode)"
  _data="{\"text\": \"$_content\"}"

echo "$_content"
echo "$_data"

  if _post "$_data" "$SLACK_WEBHOOK_URL"; then
    # shellcheck disable=SC2154
    if [ -z "$response" ]; then
      _info "slack send sccess."
      return 0
    fi
  fi
  _err "slack send error."
  _err "$response"
  return 1

}
