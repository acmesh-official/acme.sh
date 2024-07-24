#!/usr/bin/env sh

#Support Microsoft Teams webhooks

#TEAMS_WEBHOOK_URL=""

teams_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  _color_success="Good"
  _color_danger="Attention"
  _color_muted="Accent"

  TEAMS_WEBHOOK_URL="${TEAMS_WEBHOOK_URL:-$(_readaccountconf_mutable TEAMS_WEBHOOK_URL)}"
  if [ -z "$TEAMS_WEBHOOK_URL" ]; then
    TEAMS_WEBHOOK_URL=""
    _err "You didn't specify a Microsoft Teams webhook url TEAMS_WEBHOOK_URL yet."
    return 1
  fi
  _saveaccountconf_mutable TEAMS_WEBHOOK_URL "$TEAMS_WEBHOOK_URL"

  export _H1="Content-Type: application/json"

  _subject=$(echo "$_subject" | _json_encode)
  _content=$(echo "$_content" | _json_encode)

  case "$_statusCode" in
  0)
    _color="${TEAMS_SUCCESS_COLOR:-$_color_success}"
    ;;
  1)
    _color="${TEAMS_ERROR_COLOR:-$_color_danger}"
    ;;
  2)
    _color="${TEAMS_SKIP_COLOR:-$_color_muted}"
    ;;
  esac

  _data="{
    \"type\": \"message\",
    \"attachments\": [
        {
            \"contentType\": \"application/vnd.microsoft.card.adaptive\",
            \"contentUrl\": null,
            \"content\": {
                \"schema\": \"http://adaptivecards.io/schemas/adaptive-card.json\",
                \"type\": \"AdaptiveCard\",
                \"version\": \"1.2\",
                \"body\": [
                    {
                        \"type\": \"TextBlock\",
                        \"size\": \"large\",
                        \"weight\": \"bolder\",
                        \"wrap\": true,
                        \"color\": \"$_color\",
                        \"text\": \"$_subject\"
                    },
                    {
                        \"type\": \"TextBlock\",
                        \"text\": \"$_content\",
                        \"wrap\": true
                    }
                ]
            }
        }
    ]
}"

  if response=$(_post "$_data" "$TEAMS_WEBHOOK_URL"); then
    if ! _contains "$response" error; then
      _info "teams send success."
      return 0
    fi
  fi
  _err "teams send error."
  _err "$response"
  return 1
}
