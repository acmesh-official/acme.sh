#!/usr/bin/env sh

#Support Healthchecks.io (hosted or self-hosted)
#https://healthchecks.io/docs/http_api/

#Required:
#HEALTHCHECKS_URL="https://hc-ping.com/your-uuid"

#Use with --notify-level 3, so a ping is sent on every cron run, even when
#all certs are skipped. Otherwise Healthchecks reports the check as down.

healthchecks_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  HEALTHCHECKS_URL="${HEALTHCHECKS_URL:-$(_readaccountconf_mutable HEALTHCHECKS_URL)}"
  if [ -z "$HEALTHCHECKS_URL" ]; then
    HEALTHCHECKS_URL=""
    _err "You didn't specify the Healthchecks.io ping url HEALTHCHECKS_URL yet."
    _err "Example: export HEALTHCHECKS_URL=\"https://hc-ping.com/your-uuid\""
    return 1
  fi
  _saveaccountconf_mutable HEALTHCHECKS_URL "$HEALTHCHECKS_URL"

  _hc_url="${HEALTHCHECKS_URL%/}"
  case "$_statusCode" in
  0 | 2) ;;
  1)
    _hc_url="$_hc_url/fail"
    ;;
  *)
    _hc_url="$_hc_url/log"
    ;;
  esac

  _data="$_subject

$_content"

  response="$(_post "$_data" "$_hc_url" "" "POST" "text/plain")"

  if [ "$?" = "0" ] && _startswith "$response" "OK"; then
    _info "healthchecks ping success."
    return 0
  fi
  _err "healthchecks ping error."
  _err "$response"
  return 1
}
