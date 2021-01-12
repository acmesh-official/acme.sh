#!/usr/bin/env sh

#Support Telegram Bots

#TELEGRAM_BOT_APITOKEN=""
#TELEGRAM_BOT_CHATID=""

telegram_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  TELEGRAM_BOT_APITOKEN="${TELEGRAM_BOT_APITOKEN:-$(_readaccountconf_mutable TELEGRAM_BOT_APITOKEN)}"
  if [ -z "$TELEGRAM_BOT_APITOKEN" ]; then
    TELEGRAM_BOT_APITOKEN=""
    _err "You didn't specify a Telegram BOT API Token TELEGRAM_BOT_APITOKEN yet."
    return 1
  fi
  _saveaccountconf_mutable TELEGRAM_BOT_APITOKEN "$TELEGRAM_BOT_APITOKEN"

  TELEGRAM_BOT_CHATID="${TELEGRAM_BOT_CHATID:-$(_readaccountconf_mutable TELEGRAM_BOT_CHATID)}"
  if [ -z "$TELEGRAM_BOT_CHATID" ]; then
    TELEGRAM_BOT_CHATID=""
    _err "You didn't specify a Telegram Chat id TELEGRAM_BOT_CHATID yet."
    return 1
  fi
  _saveaccountconf_mutable TELEGRAM_BOT_CHATID "$TELEGRAM_BOT_CHATID"

  _content="$(printf "*%s*\n%s" "$_subject" "$_content" | _json_encode)"
  _data="{\"text\": \"$_content\", "
  _data="$_data\"chat_id\": \"$TELEGRAM_BOT_CHATID\", "
  _data="$_data\"parse_mode\": \"markdown\", "
  _data="$_data\"disable_web_page_preview\": \"1\"}"

  export _H1="Content-Type: application/json"
  _telegram_bot_url="https://api.telegram.org/bot${TELEGRAM_BOT_APITOKEN}/sendMessage"
  if _post "$_data" "$_telegram_bot_url"; then
    # shellcheck disable=SC2154
    _message=$(printf "%s\n" "$response" | sed -n 's/.*"ok":\([^,]*\).*/\1/p')
    if [ "$_message" = "true" ]; then
      _info "telegram send success."
      return 0
    fi
  fi
  _err "telegram send error."
  _err "$response"
  return 1
}
