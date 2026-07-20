#!/usr/bin/env sh

# support ntfy

#NTFY_URL="https://ntfy.sh"
#NTFY_TOPIC="xxxxxxxxxxxxx"
#NTFY_TOKEN="xxxxxxxxxxxxx"

ntfy_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  _priority_default="default"
  _priority_error="high"

  _tag_success="white_check_mark"
  _tag_error="warning"
  _tag_info="information_source"

  NTFY_URL="${NTFY_URL:-$(_readaccountconf_mutable NTFY_URL)}"
  if [ "$NTFY_URL" ]; then
    _saveaccountconf_mutable NTFY_URL "$NTFY_URL"
  fi

  NTFY_TOPIC="${NTFY_TOPIC:-$(_readaccountconf_mutable NTFY_TOPIC)}"
  if [ "$NTFY_TOPIC" ]; then
    _saveaccountconf_mutable NTFY_TOPIC "$NTFY_TOPIC"
  fi

  NTFY_TOKEN="${NTFY_TOKEN:-$(_readaccountconf_mutable NTFY_TOKEN)}"
  if [ "$NTFY_TOKEN" ]; then
    _saveaccountconf_mutable NTFY_TOKEN "$NTFY_TOKEN"
    export _H1="Authorization: Bearer $NTFY_TOKEN"
  fi

  case "$_statusCode" in
  0)
    _priority="$_priority_default"
    _tag="$_tag_success"
    ;;
  1)
    _priority="$_priority_error"
    _tag="$_tag_error"
    ;;
  2)
    _priority="$_priority_default"
    _tag="$_tag_info"
    ;;
  esac

  export _H2="Priority: $_priority"
  export _H3="Tags: $_tag"
  export _H4="Title: $PROJECT_NAME: $_subject"

  _data="$_content"
  response="$(_post "$_data" "$NTFY_URL/$NTFY_TOPIC" "" "POST" "")"

  if [ "$?" = "0" ] && _contains "$response" "expires"; then
    _info "ntfy event fired success."
    return 0
  fi

  _err "ntfy event fired error."
  _err "$response"
  return 1
}
