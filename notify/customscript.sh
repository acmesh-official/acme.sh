#!/usr/bin/env sh

# Support custom notification script

# CUSTOMSCRIPT_PATH="/usr/local/bin/acme-notification.sh"

customscript_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  CUSTOMSCRIPT_PATH="${CUSTOMSCRIPT_PATH:-$(_readaccountconf_mutable CUSTOMSCRIPT_PATH)}"
  if [ -n "$CUSTOMSCRIPT_PATH" ] && ! _exists "$CUSTOMSCRIPT_PATH"; then
    _err "It seems that the command $CUSTOMSCRIPT_PATH is not in path."
    return 1
  fi

  if [ -n "$CUSTOMSCRIPT_PATH" ]; then
    _saveaccountconf_mutable CUSTOMSCRIPT_PATH "$CUSTOMSCRIPT_PATH"
  else
    _clearaccountconf "CUSTOMSCRIPT_PATH"
  fi

  result=$(eval "'$CUSTOMSCRIPT_PATH' '$_subject' '$_content' '$_statusCode'" 2>&1)

  if [ $? -ne 0 ]; then
    _debug "custom script execution error."
    _err "$result"
    return 1
  fi

  _debug "custom script executed successfully."
  return 0
}
