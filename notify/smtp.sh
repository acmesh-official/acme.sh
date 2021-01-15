#!/usr/bin/env sh

smtp_send() {
  if ! _exists "mailx"; then
    _err "You must install mailx to send email by SMTP"
    return 1
  fi

  SMTP_FROM="${SMTP_FROM:-$(_readaccountconf_mutable SMTP_FROM)}"
  if [ -z "$SMTP_FROM" ]; then
    _err "You must define SMTP_FROM as the sender email address."
    return 1
  fi

  SMTP_TO="${SMTP_TO:-$(_readaccountconf_mutable SMTP_TO)}"
  if [ -z "$SMTP_TO" ]; then
    _err "You must define SMTP_TO as the recipient email address."
    return 1
  fi

  SMTP_HOST="${SMTP_HOST:-$(_readaccountconf_mutable SMTP_HOST)}"
  if [ -z "$SMTP_HOST" ]; then
    _err "You must define SMTP_HOST as the SMTP server hostname."
    return 1
  fi

  SMTP_USERNAME="${SMTP_USERNAME:-$(_readaccountconf_mutable SMTP_USERNAME)}"
  SMTP_PASSWORD="${SMTP_PASSWORD:-$(_readaccountconf_mutable SMTP_PASSWORD)}"
  SMTP_CONTEXT="${SMTP_CONTEXT:-$(_readaccountconf_mutable SMTP_CONTEXT)}"

  _saveaccountconf_mutable SMTP_FROM "$SMTP_FROM"
  _saveaccountconf_mutable SMTP_TO "$SMTP_TO"
  _saveaccountconf_mutable SMTP_HOST "$SMTP_HOST"
  _saveaccountconf_mutable SMTP_USERNAME "$SMTP_USERNAME"
  _saveaccountconf_mutable SMTP_PASSWORD "$SMTP_PASSWORD"
  _saveaccountconf_mutable SMTP_CONTEXT "$SMTP_CONTEXT" "base64"

  if ! _smtp_send "$@"; then
    _err "$smtp_send_output"
    return 1
  fi

  return 0
}

_smtp_send() {
  _subject="${1}"
  _content="${2}"
  _statusCode="${3}"
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  _debug "SMTP_FROM" "$SMTP_FROM"
  _debug "SMTP_TO" "$SMTP_TO"
  _debug "SMTP_HOST" "$SMTP_HOST"
  _debug "SMTP_USERNAME" "$SMTP_USERNAME"
  _debug "SMTP_PASSWORD" "$SMTP_PASSWORD"

  if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -ge "$DEBUG_LEVEL_2" ]; then
    smtp_debug="True"
  else
    smtp_debug=""
  fi

  smtp_send_output="$(echo "${_content}" | mailx -v \
                      -s "${_subject}" \
                      -S ssl-verify=ignore\
                      -S smtp="${SMTP_HOST}" \
                      -S smtp-auth=login \
                      -S smtp-auth-user="${SMTP_USERNAME}" \
                      -S smtp-auth-password="${SMTP_PASSWORD}" \
                      -S from="${SMTP_FROM}" \
                      "${SMTP_TO}" 2>&1)"

  _debug "smtp_send_output" "$smtp_send_output"

  if [[ $smtp_send_output =~ "message not sent" ]]; then
    return 1
  else
    return 0
  fi
}
