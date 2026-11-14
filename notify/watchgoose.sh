#!/usr/bin/env sh

#Support Watchgoose heartbeat monitoring
#https://watchgoose.com/docs/http_api/

#Required:
#WATCHGOOSE_URL="https://watchgoose.com/ping/your-uuid"

#Use with --notify-level 3 --notify-mode 0, so one ping is sent on every
#cron run, even when all certs are skipped, carrying the worst result.
#Otherwise Watchgoose reports the check as down, or a later success hides
#an earlier failure.

watchgoose_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  WATCHGOOSE_URL="${WATCHGOOSE_URL:-$(_readaccountconf_mutable WATCHGOOSE_URL)}"
  if [ -z "$WATCHGOOSE_URL" ]; then
    WATCHGOOSE_URL=""
    _err "You didn't specify the Watchgoose ping url WATCHGOOSE_URL yet."
    _err "Example: export WATCHGOOSE_URL=\"https://watchgoose.com/ping/your-uuid\""
    return 1
  fi
  _saveaccountconf_mutable WATCHGOOSE_URL "$WATCHGOOSE_URL"

  _wg_url="${WATCHGOOSE_URL%/}"
  case "$_statusCode" in
  0 | 2) ;;
  1)
    _wg_url="$_wg_url/fail"
    ;;
  *)
    _wg_url="$_wg_url/log"
    ;;
  esac

  _data="$_subject

$_content"

  response="$(_post "$_data" "$_wg_url" "" "POST" "text/plain")"

  if [ "$?" = "0" ] && [ "$response" = "OK" ]; then
    _info "watchgoose ping success."
    return 0
  fi
  _err "watchgoose ping error."
  _err "$response"
  return 1
}
