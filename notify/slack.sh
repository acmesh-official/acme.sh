#!/usr/bin/env sh

#Support Slack webhooks

#SLACK_WEBHOOK_URL=""
#SLACK_CHANNEL=""
#SLACK_USERNAME=""

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

  SLACK_CHANNEL="${SLACK_CHANNEL:-$(_readaccountconf_mutable SLACK_CHANNEL)}"
  if [ -n "$SLACK_CHANNEL" ]; then
    _saveaccountconf_mutable SLACK_CHANNEL "$SLACK_CHANNEL"
  fi

  SLACK_USERNAME="${SLACK_USERNAME:-$(_readaccountconf_mutable SLACK_USERNAME)}"
  if [ -n "$SLACK_USERNAME" ]; then
    _saveaccountconf_mutable SLACK_USERNAME "$SLACK_USERNAME"
  fi

  export _H1="Content-Type: application/json"

  _content="$(printf "*%s*\n%s" "$_subject" "$_content" | _json_encode)"
  _data="{\"text\": \"$_content\", "
  if [ -n "$SLACK_CHANNEL" ]; then
    _data="$_data\"channel\": \"$SLACK_CHANNEL\", "
  fi
  if [ -n "$SLACK_USERNAME" ]; then
    _data="$_data\"username\": \"$SLACK_USERNAME\", "
  fi
  _data="$_data\"mrkdwn\": \"true\"}"

  if _post "$_data" "$SLACK_WEBHOOK_URL"; then
    # shellcheck disable=SC2154
    if [ "$response" = "ok" ]; then
      _info "slack send success."
      return 0
    fi
  fi
  _err "slack send error."
  _err "$response"
  return 1
}
