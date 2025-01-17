#!/usr/bin/env sh

# Support mattermost bots

#MATTERMOST_API_URL=""
#MATTERMOST_CHANNEL_ID=""
#MATTERMOST_BOT_TOKEN=""

mattermost_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  MATTERMOST_API_URL="${MATTERMOST_API_URL:-$(_readaccountconf_mutable MATTERMOST_API_URL)}"
  if [ -z "$MATTERMOST_API_URL" ]; then
    _err "You didn't specify a Mattermost API URL MATTERMOST_API_URL yet."
    return 1
  fi
  _saveaccountconf_mutable MATTERMOST_API_URL "$MATTERMOST_API_URL"

  MATTERMOST_CHANNEL_ID="${MATTERMOST_CHANNEL_ID:-$(_readaccountconf_mutable MATTERMOST_CHANNEL_ID)}"
  if [ -z "$MATTERMOST_CHANNEL_ID" ]; then
    _err "You didn't specify a Mattermost channel id MATTERMOST_CHANNEL_ID yet."
    return 1
  fi
  _saveaccountconf_mutable MATTERMOST_CHANNEL_ID "$MATTERMOST_CHANNEL_ID"

  MATTERMOST_BOT_TOKEN="${MATTERMOST_BOT_TOKEN:-$(_readaccountconf_mutable MATTERMOST_BOT_TOKEN)}"
  if [ -z "$MATTERMOST_BOT_TOKEN" ]; then
    _err "You didn't specify a Mattermost bot API token MATTERMOST_BOT_TOKEN yet."
    return 1
  fi
  _saveaccountconf_mutable MATTERMOST_BOT_TOKEN "$MATTERMOST_BOT_TOKEN"

  _content="$(printf "*%s*\n%s" "$_subject" "$_content" | _json_encode)"
  _data="{\"channel_id\": \"$MATTERMOST_CHANNEL_ID\", "
  _data="$_data\"message\": \"$_content\"}"

  export _H1="Authorization: Bearer $MATTERMOST_BOT_TOKEN"
  response=""
  if _post "$_data" "$MATTERMOST_API_URL" "" "POST" "application/json; charset=utf-8"; then
    MATTERMOST_RESULT_OK=$(echo "$response" | _egrep_o 'create_at')
    if [ "$?" = "0" ] && [ "$MATTERMOST_RESULT_OK" ]; then
      _info "mattermost send success."
      return 0
    fi
  fi
  _err "mattermost send error."
  _err "$response"
  return 1
}
