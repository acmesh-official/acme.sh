#!/usr/bin/env sh

# support ntfy

#NTFY_URL="https://ntfy.sh"
#NTFY_TOPIC="xxxxxxxxxxxxx"
#NTFY_TOKEN="xxxxxxxxxxxxx"
#optional extra request headers, '|' separated, e.g. for a self hosted ntfy
#behind Cloudflare Access:
#NTFY_HEADERS="CF-Access-Client-Id: xxxxxxxx.access|CF-Access-Client-Secret: e18fca2dxxxx"

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

  NTFY_HEADERS="${NTFY_HEADERS:-$(_readaccountconf_mutable NTFY_HEADERS)}"
  if [ "$NTFY_HEADERS" ]; then
    _saveaccountconf_mutable NTFY_HEADERS "$NTFY_HEADERS"
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

  #the request can carry only the five _H1.._H5 headers: _H2.._H4 hold
  #Priority, Tags and Title, and _H1 holds the token, so the extra headers
  #in NTFY_HEADERS fill the remaining free slots
  _ntfy_free="2"
  if [ "$NTFY_TOKEN" ]; then
    _ntfy_free="1"
  fi
  _ntfy_count=0
  _ntfy_extra1=""
  _ntfy_extra2=""
  #line breaks cannot be saved in the account conf, so '|' separates the
  #headers; real line breaks are normalized to separators too
  _ntfy_rest="$(printf "%s" "$NTFY_HEADERS" | tr '\r\n' '||')"
  while [ "$_ntfy_rest" ]; do
    _ntfy_header="${_ntfy_rest%%|*}"
    if [ "$_ntfy_header" = "$_ntfy_rest" ]; then
      _ntfy_rest=""
    else
      _ntfy_rest="${_ntfy_rest#*|}"
    fi
    _ntfy_header="$(printf "%s" "$_ntfy_header" | sed 's/^ *//;s/ *$//')"
    if [ "$_ntfy_header" ]; then
      _ntfy_count=$((_ntfy_count + 1))
      if [ "$_ntfy_count" = "1" ]; then
        _ntfy_extra1="$_ntfy_header"
      elif [ "$_ntfy_count" = "2" ]; then
        _ntfy_extra2="$_ntfy_header"
      fi
    fi
  done
  if [ "$_ntfy_count" -gt "$_ntfy_free" ]; then
    _err "Too many headers in NTFY_HEADERS: the request can carry at most $_ntfy_free extra header(s)."
    return 1
  fi
  if [ "$_ntfy_extra1" ]; then
    _debug "ntfy extra header count" "$_ntfy_count"
    if [ "$NTFY_TOKEN" ]; then
      export _H5="$_ntfy_extra1"
    else
      export _H1="$_ntfy_extra1"
      if [ "$_ntfy_extra2" ]; then
        export _H5="$_ntfy_extra2"
      fi
    fi
  fi

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
