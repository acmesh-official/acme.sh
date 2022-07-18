#!/usr/bin/env sh

#Support Slack APP notifications

#SLACK_APP_CHANNEL=""
#SLACK_APP_TOKEN=""

slack_app_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  SLACK_APP_CHANNEL="${SLACK_APP_CHANNEL:-$(_readaccountconf_mutable SLACK_APP_CHANNEL)}"
  if [ -n "$SLACK_APP_CHANNEL" ]; then
    _saveaccountconf_mutable SLACK_APP_CHANNEL "$SLACK_APP_CHANNEL"
  fi

  SLACK_APP_TOKEN="${SLACK_APP_TOKEN:-$(_readaccountconf_mutable SLACK_APP_TOKEN)}"
  if [ -n "$SLACK_APP_TOKEN" ]; then
    _saveaccountconf_mutable SLACK_APP_TOKEN "$SLACK_APP_TOKEN"
  fi

  _content="$(printf "*%s*\n%s" "$_subject" "$_content" | _json_encode)"
  _data="{\"text\": \"$_content\", "
  if [ -n "$SLACK_APP_CHANNEL" ]; then
    _data="$_data\"channel\": \"$SLACK_APP_CHANNEL\", "
  fi
  _data="$_data\"mrkdwn\": \"true\"}"

  export _H1="Authorization: Bearer $SLACK_APP_TOKEN"

  SLACK_APP_API_URL="https://slack.com/api/chat.postMessage"
  if _post "$_data" "$SLACK_APP_API_URL" "" "POST" "application/json; charset=utf-8"; then
    # shellcheck disable=SC2154
    SLACK_APP_RESULT_OK=$(echo "$response" | _egrep_o 'ok" *: *true')
    if [ "$?" = "0" ] && [ "$SLACK_APP_RESULT_OK" ]; then
      _info "slack send success."
      return 0
    fi
  fi
  _err "slack send error."
  _err "$response"
  return 1
}
