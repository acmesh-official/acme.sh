#!/usr/bin/env sh

# Support iOS Bark Notification

# Every parameter explained: https://github.com/Finb/bark-server/blob/master/docs/API_V2.md#push

# BARK_API_URL="https://api.day.app/xxxx" (required)
# BARK_GROUP="ACME" (optional)
# BARK_SOUND="alarm" (optional)
# BARK_LEVEL="active" (optional)
# BARK_BADGE=0 (optional)
# BARK_AUTOMATICALLYCOPY="1" (optional)
# BARK_COPY="My clipboard Content" (optional)
# BARK_ICON="https://example.com/icon.png" (optional)
# BARK_ISARCHIVE="1" (optional)
# BARK_URL="https://example.com" (optional)

# subject content statusCode
bark_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" # 0: success, 1: error, 2: skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  _content=$(echo "$_content" | _url_encode)
  _subject=$(echo "$_subject" | _url_encode)

  BARK_API_URL="${BARK_API_URL:-$(_readaccountconf_mutable BARK_API_URL)}"
  if [ -z "$BARK_API_URL" ]; then
    _err "You didn't specify a Bark API URL BARK_API_URL yet."
    _err "You can download Bark from App Store and get yours."
    return 1
  fi
  _saveaccountconf_mutable BARK_API_URL "$BARK_API_URL"

  BARK_GROUP="${BARK_GROUP:-$(_readaccountconf_mutable BARK_GROUP)}"
  if [ -z "$BARK_GROUP" ]; then
    BARK_GROUP="ACME"
    _info "The BARK_GROUP is not set, so use the default ACME as group name."
  else
    _saveaccountconf_mutable BARK_GROUP "$BARK_GROUP"
  fi

  BARK_SOUND="${BARK_SOUND:-$(_readaccountconf_mutable BARK_SOUND)}"
  if [ -n "$BARK_SOUND" ]; then
    _saveaccountconf_mutable BARK_SOUND "$BARK_SOUND"
  fi

  BARK_LEVEL="${BARK_LEVEL:-$(_readaccountconf_mutable BARK_LEVEL)}"
  if [ -n "$BARK_LEVEL" ]; then
    _saveaccountconf_mutable BARK_LEVEL "$BARK_LEVEL"
  fi

  BARK_BADGE="${BARK_BADGE:-$(_readaccountconf_mutable BARK_BADGE)}"
  if [ -n "$BARK_BADGE" ]; then
    _saveaccountconf_mutable BARK_BADGE "$BARK_BADGE"
  fi

  BARK_AUTOMATICALLYCOPY="${BARK_AUTOMATICALLYCOPY:-$(_readaccountconf_mutable BARK_AUTOMATICALLYCOPY)}"
  if [ -n "$BARK_AUTOMATICALLYCOPY" ]; then
    _saveaccountconf_mutable BARK_AUTOMATICALLYCOPY "$BARK_AUTOMATICALLYCOPY"
  fi

  BARK_COPY="${BARK_COPY:-$(_readaccountconf_mutable BARK_COPY)}"
  if [ -n "$BARK_COPY" ]; then
    _saveaccountconf_mutable BARK_COPY "$BARK_COPY"
  fi

  BARK_ICON="${BARK_ICON:-$(_readaccountconf_mutable BARK_ICON)}"
  if [ -n "$BARK_ICON" ]; then
    _saveaccountconf_mutable BARK_ICON "$BARK_ICON"
  fi

  BARK_ISARCHIVE="${BARK_ISARCHIVE:-$(_readaccountconf_mutable BARK_ISARCHIVE)}"
  if [ -n "$BARK_ISARCHIVE" ]; then
    _saveaccountconf_mutable BARK_ISARCHIVE "$BARK_ISARCHIVE"
  fi

  BARK_URL="${BARK_URL:-$(_readaccountconf_mutable BARK_URL)}"
  if [ -n "$BARK_URL" ]; then
    _saveaccountconf_mutable BARK_URL "$BARK_URL"
  fi

  _params=""

  if [ -n "$BARK_SOUND" ]; then
    _params="$_params&sound=$BARK_SOUND"
  fi
  if [ -n "$BARK_GROUP" ]; then
    _params="$_params&group=$BARK_GROUP"
  fi
  if [ -n "$BARK_LEVEL" ]; then
    _params="$_params&level=$BARK_LEVEL"
  fi
  if [ -n "$BARK_BADGE" ]; then
    _params="$_params&badge=$BARK_BADGE"
  fi
  if [ -n "$BARK_AUTOMATICALLYCOPY" ]; then
    _params="$_params&automaticallyCopy=$BARK_AUTOMATICALLYCOPY"
  fi
  if [ -n "$BARK_COPY" ]; then
    _params="$_params&copy=$BARK_COPY"
  fi
  if [ -n "$BARK_ICON" ]; then
    _params="$_params&icon=$BARK_ICON"
  fi
  if [ -n "$BARK_ISARCHIVE" ]; then
    _params="$_params&isArchive=$BARK_ISARCHIVE"
  fi
  if [ -n "$BARK_URL" ]; then
    _params="$_params&url=$BARK_URL"
  fi

  _params=$(echo "$_params" | sed 's/^&//') # remove leading '&' if exists

  response="$(_get "$BARK_API_URL/$_subject/$_content?$_params")"

  if [ "$?" = "0" ] && _contains "$response" "success"; then
    _info "Bark API fired success."
    return 0
  fi

  _err "Bark API fired error."
  _err "$response"
  return 1
}
