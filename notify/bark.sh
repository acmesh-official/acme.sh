#!/usr/bin/env sh

#Support iOS Bark Notification

#BARK_API_URL="https://api.day.app/xxxx"
#BARK_SOUND="yyyy"
#BARK_GROUP="zzzz"

# subject  content statusCode
bark_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  BARK_API_URL="${BARK_API_URL:-$(_readaccountconf_mutable BARK_API_URL)}"
  if [ -z "$BARK_API_URL" ]; then
    BARK_API_URL=""
    _err "You didn't specify a Bark API URL BARK_API_URL yet."
    _err "You can download Bark from App Store and get yours."
    return 1
  fi
  _saveaccountconf_mutable BARK_API_URL "$BARK_API_URL"

  BARK_SOUND="${BARK_SOUND:-$(_readaccountconf_mutable BARK_SOUND)}"
  _saveaccountconf_mutable BARK_SOUND "$BARK_SOUND"

  BARK_GROUP="${BARK_GROUP:-$(_readaccountconf_mutable BARK_GROUP)}"
  if [ -z "$BARK_GROUP" ]; then
    BARK_GROUP="ACME"
    _info "The BARK_GROUP is not set, so use the default ACME as group name."
  else
    _saveaccountconf_mutable BARK_GROUP "$BARK_GROUP"
  fi

  _content=$(echo "$_content" | _url_encode)
  _subject=$(echo "$_subject" | _url_encode)

  response="$(_get "$BARK_API_URL/$_subject/$_content?sound=$BARK_SOUND&group=$BARK_GROUP")"

  if [ "$?" = "0" ] && _contains "$response" "success"; then
    _info "Bark API fired success."
    return 0
  fi

  _err "Bark API fired error."
  _err "$response"
  return 1
}
