#!/usr/bin/env sh

#Support local mail app

#MAIL_BIN="sendmail"
#MAIL_FROM="yyyy@gmail.com"
#MAIL_TO="yyyy@gmail.com"
#MAIL_NOVALIDATE=""

mail_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  MAIL_NOVALIDATE="${MAIL_NOVALIDATE:-$(_readaccountconf_mutable MAIL_NOVALIDATE)}"
  if [ -n "$MAIL_NOVALIDATE" ]; then
    _saveaccountconf_mutable MAIL_NOVALIDATE 1
  else
    _clearaccountconf "MAIL_NOVALIDATE"
  fi

  MAIL_BIN="${MAIL_BIN:-$(_readaccountconf_mutable MAIL_BIN)}"
  if [ -n "$MAIL_BIN" ] && ! _exists "$MAIL_BIN"; then
    _err "It seems that the command $MAIL_BIN is not in path."
    return 1
  fi
  _MAIL_BIN=$(_mail_bin)
  if [ -n "$MAIL_BIN" ]; then
    _saveaccountconf_mutable MAIL_BIN "$MAIL_BIN"
  else
    _clearaccountconf "MAIL_BIN"
  fi

  MAIL_FROM="${MAIL_FROM:-$(_readaccountconf_mutable MAIL_FROM)}"
  if [ -n "$MAIL_FROM" ]; then
    if ! _mail_valid "$MAIL_FROM"; then
      _err "It seems that the MAIL_FROM=$MAIL_FROM is not a valid email address."
      return 1
    fi

    _saveaccountconf_mutable MAIL_FROM "$MAIL_FROM"
  fi

  MAIL_TO="${MAIL_TO:-$(_readaccountconf_mutable MAIL_TO)}"
  if [ -n "$MAIL_TO" ]; then
    if ! _mail_valid "$MAIL_TO"; then
      _err "It seems that the MAIL_TO=$MAIL_TO is not a valid email address."
      return 1
    fi

    _saveaccountconf_mutable MAIL_TO "$MAIL_TO"
  else
    MAIL_TO="$(_readaccountconf ACCOUNT_EMAIL)"
    if [ -z "$MAIL_TO" ]; then
      _err "It seems that account email is empty."
      return 1
    fi
  fi

  contenttype="text/plain; charset=utf-8"
  subject="=?UTF-8?B?$(echo "$_subject" | _base64)?="
  result=$({ _mail_body | eval "$(_mail_cmnd)"; } 2>&1)

  # shellcheck disable=SC2181
  if [ $? -ne 0 ]; then
    _debug "mail send error."
    _err "$result"
    return 1
  fi

  _debug "mail send success."
  return 0
}

_mail_bin() {
  if [ -n "$MAIL_BIN" ]; then
    _MAIL_BIN="$MAIL_BIN"
  elif _exists "sendmail"; then
    _MAIL_BIN="sendmail"
  elif _exists "ssmtp"; then
    _MAIL_BIN="ssmtp"
  elif _exists "mutt"; then
    _MAIL_BIN="mutt"
  elif _exists "mail"; then
    _MAIL_BIN="mail"
  else
    _err "Please install sendmail, ssmtp, mutt or mail first."
    return 1
  fi

  echo "$_MAIL_BIN"
}

_mail_cmnd() {
  case $(basename "$_MAIL_BIN") in
    sendmail)
      if [ -n "$MAIL_FROM" ]; then
        echo "'$_MAIL_BIN' -f '$MAIL_FROM' '$MAIL_TO'"
      else
        echo "'$_MAIL_BIN' '$MAIL_TO'"
      fi
      ;;
    ssmtp)
      echo "'$_MAIL_BIN' '$MAIL_TO'"
      ;;
    mutt | mail)
      echo "'$_MAIL_BIN' -s '$_subject' '$MAIL_TO'"
      ;;
    *)
      _err "Command $MAIL_BIN is not supported, use sendmail, ssmtp, mutt or mail."
      return 1
      ;;
  esac
}

_mail_body() {
  case $(basename "$_MAIL_BIN") in
    sendmail | ssmtp)
      if [ -n "$MAIL_FROM" ]; then
        echo "From: $MAIL_FROM"
      fi

      echo "To: $MAIL_TO"
      echo "Subject: $subject"
      echo "Content-Type: $contenttype"
      echo
      ;;
  esac

  echo "$_content"
}

_mail_valid() {
  [ -n "$MAIL_NOVALIDATE" ] || _contains "$1" "@"
}
