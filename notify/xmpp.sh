#!/usr/bin/env sh

#Support xmpp via sendxmpp

#XMPP_BIN="/usr/bin/sendxmpp"
#XMPP_BIN_ARGS="-n -t --tls-ca-path=/etc/ssl/certs"
#XMPP_TO="zzzz@example.com"

xmpp_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  XMPP_BIN="${XMPP_BIN:-$(_readaccountconf_mutable XMPP_BIN)}"
  if [ -n "$XMPP_BIN" ] && ! _exists "$XMPP_BIN"; then
    _err "It seems that the command $XMPP_BIN is not in path."
    return 1
  fi
  _XMPP_BIN=$(_xmpp_bin)
  if [ -n "$XMPP_BIN" ]; then
    _saveaccountconf_mutable XMPP_BIN "$XMPP_BIN"
  else
    _clearaccountconf "XMPP_BIN"
  fi

  XMPP_BIN_ARGS="${XMPP_BIN_ARGS:-$(_readaccountconf_mutable XMPP_BIN_ARGS)}"
  if [ -n "$XMPP_BIN_ARGS" ]; then
    _saveaccountconf_mutable XMPP_BIN_ARGS "$XMPP_BIN_ARGS"
  else
    _clearaccountconf "XMPP_BIN_ARGS"
  fi

  XMPP_TO="${XMPP_TO:-$(_readaccountconf_mutable XMPP_TO)}"
  if [ -n "$XMPP_TO" ]; then
    if ! _xmpp_valid "$XMPP_TO"; then
      _err "It seems that the XMPP_TO=$XMPP_TO is not a valid xmpp address."
      return 1
    fi

    _saveaccountconf_mutable XMPP_TO "$XMPP_TO"
  fi

  result=$({ _xmpp_message | eval "$(_xmpp_cmnd)"; } 2>&1)

  # shellcheck disable=SC2181
  if [ $? -ne 0 ]; then
    _debug "xmpp send error."
    _err "$result"
    return 1
  fi

  _debug "xmpp send success."
  return 0
}

_xmpp_bin() {
  if [ -n "$XMPP_BIN" ]; then
    _XMPP_BIN="$XMPP_BIN"
  elif _exists "sendxmpp"; then
    _XMPP_BIN="sendxmpp"
  else
    _err "Please install sendxmpp first."
    return 1
  fi

  echo "$_XMPP_BIN"
}

_xmpp_cmnd() {
  case $(basename "$_XMPP_BIN") in
    sendxmpp)
      echo "'$_XMPP_BIN' '$XMPP_TO' $XMPP_BIN_ARGS"
      ;;
    *)
      _err "Command $XMPP_BIN is not supported, use sendxmpp."
      return 1
      ;;
  esac
}

_xmpp_message() {
  echo "$_subject"
}

_xmpp_valid() {
  _contains "$1" "@"
}
