#!/usr/bin/env sh

#Support sendmail

#SENDMAIL_BIN="sendmail"
#SENDMAIL_FROM="yyyy@gmail.com"
#SENDMAIL_TO="yyyy@gmail.com"

sendmail_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  SENDMAIL_BIN="${SENDMAIL_BIN:-$(_readaccountconf_mutable SENDMAIL_BIN)}"
  if [ -z "$SENDMAIL_BIN" ]; then
    SENDMAIL_BIN="sendmail"
    _info "The SENDMAIL_BIN is not set, so use the default value: $SENDMAIL_BIN"
  fi
  if ! _exists "$SENDMAIL_BIN"; then
    _err "Please install sendmail first."
    return 1
  fi
  _saveaccountconf_mutable SENDMAIL_BIN "$SENDMAIL_BIN"

  SENDMAIL_FROM="${SENDMAIL_FROM:-$(_readaccountconf_mutable SENDMAIL_FROM)}"
  if [ -z "$SENDMAIL_FROM" ]; then
    SENDMAIL_FROM="$USER@$HOSTNAME"
    _info "The SENDMAIL_FROM is not set, so use the default value: $SENDMAIL_FROM"
  fi
  _saveaccountconf_mutable SENDMAIL_FROM "$SENDMAIL_FROM"

  SENDMAIL_TO="${SENDMAIL_TO:-$(_readaccountconf_mutable SENDMAIL_TO)}"
  if [ -z "$SENDMAIL_TO" ]; then
    SENDMAIL_TO="$(_readaccountconf ACCOUNT_EMAIL)"
    _info "The SENDMAIL_TO is not set, so use the account email: $SENDMAIL_TO"
  fi
  _saveaccountconf_mutable SENDMAIL_TO "$SENDMAIL_TO"

  subject="=?UTF-8?B?$(echo "$_subject" | _base64)?="
  error=$( { echo "From: $SENDMAIL_FROM
To: $SENDMAIL_TO
Subject: $subject
Content-Type: text/plain; charset=utf-8

$_content
" | "$SENDMAIL_BIN" -f "$SENDMAIL_FROM" "$SENDMAIL_TO"; } 2>&1 )

  if [ $? -ne 0 ]; then
    _debug "sendmail send error."
    _err "$error"
    return 1
  fi

  _debug "sendmail send success."
  return 0
}
