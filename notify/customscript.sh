#!/usr/bin/env sh

# Support calling a custom script for notifications
#
# export CUSTOMSCRIPT_PATH="/usr/local/bin/acme-notification.sh"
#
# The script is called with three arguments:
#   $1  subject
#   $2  content
#   $3  status code (0: success, 1: error, 2: skipped)

customscript_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  CUSTOMSCRIPT_PATH="${CUSTOMSCRIPT_PATH:-$(_readaccountconf_mutable CUSTOMSCRIPT_PATH)}"
  if [ -z "$CUSTOMSCRIPT_PATH" ]; then
    _err "You didn't specify the custom script path CUSTOMSCRIPT_PATH yet."
    return 1
  fi
  if ! _exists "$CUSTOMSCRIPT_PATH"; then
    _err "The custom script $CUSTOMSCRIPT_PATH does not exist or is not executable."
    return 1
  fi
  _saveaccountconf_mutable CUSTOMSCRIPT_PATH "$CUSTOMSCRIPT_PATH"

  # Invoke directly, never through eval: the subject and content contain
  # domain names and CA messages, eval would allow command injection.
  _customscript_result="$("$CUSTOMSCRIPT_PATH" "$_subject" "$_content" "$_statusCode" 2>&1)"
  _customscript_rc="$?"
  _debug2 "_customscript_result" "$_customscript_result"

  if [ "$_customscript_rc" != "0" ]; then
    _err "custom script execution error ($_customscript_rc): $_customscript_result"
    return 1
  fi

  _info "custom script executed successfully."
  return 0
}
